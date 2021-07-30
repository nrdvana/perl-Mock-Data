package Mock::Data::Charset;
use strict;
use warnings;


=head1 EXPORTABLE FUNCTIONS

=head2 charset_invlist

  my $invlist= charset_invlist($notation, $max_codepoint);

This creates an "inversion list" for a perl character set.  An inversion list describes
spans of Unicode codepoints that belong to a set.  The first element of the list is the
first codepoint member, the second element is the first codepoint following that which
is *not* a member, the third element is the element following that which *is* a member
and so on.

The first parameter is a character set described by the notation used for perl regular
expressions, without the enclosing brackets.  For example:

  charset_invlist("A-Z");             # returns [ 65, 91 ]
  charset_invlist("a-z0-9A-Z");       # returns [ 48, 58, 65, 91, 97, 123 ]
  charset_invlist("\p{space}", 0x7F); # returns [ 9, 14, 32, 33 ]

The second parameter lets you limit the search space to something smaller than the full
Unicode charset.  If you are using Perl 5.16 or later, the search is fast because
L<Unicode::UCD> does the search for you, but on older perls it has to just iterate
characters, and setting a maximum can speed things up greatly.

=cut

our $have_prop_invlist;
sub charset_invlist {
	my ($notation, $max_codepoint)= @_;
	# If the search space is small, it is probably faster to iterate and let perl do the work
	# than to parse the charset.
	if (defined $max_codepoint and $max_codepoint <= 255) {
		my $re= qr/[$notation]/;
		my @invlist;
		my $match;
		for (0..$max_codepoint) {
			next unless $match xor (chr($_) =~ $re);
			push @invlist, $_;
			$match= !$match;
		}
		return \@invlist;
	}
	else {
		$have_prop_invlist= do { require Unicode::UCD; !!Unicode::UCD->can('prop_invlist') }
			unless defined $have_prop_invlist;
		my @include;
		my @invlists;
		my @range;
		local $_= $notation;
		pos = 0;
		my $invert= /\G\^/gc;
		if (/\G]/gc) { push @include, ord ']' }
		while (pos $_ < length) {
			my $cp;
			if (/\G\\/gc) {
				if (/\Gx([0-9A-Za-z][0-9A-Za-z]?)/gc) {
					$cp= hex $1;
				}
				elsif (/\G[0-9][0-9][0-9]?/gc) {
					$cp= oct $1;
				}
				elsif (/\Gp\{[^}]+\}/gc) {
					...
				}
				else {
					/\G(.)/gc;
					$cp= ord $1;
				}
			}
			elsif (/\G-/gc) {
				if (@range == 1) {
					push @range, '-';
					next;
				}
				else {
					$cp= ord '-';
				}
			}
			else {
				/\G(.)/gc;
				$cp= ord $1;
			}
			if (@range == 1) {
				push @include, pop @range;
				push @range, $cp;
			}
			elsif (@range == 2) {
				push @invlists, [ $range[0], $cp + 1 ];
				@range= ();
			}
			else {
				push @range, $cp;
			}
			#printf "# pos %d  cp %d  range %s %s  include %s\n", pos $_, $cp, $range[0] // '(null)', $range[1] // '(null)', join(',', @include);
		}
		push @include, @range;
		# convert the include list into an inversion list
		if (@include) {
			@include= sort { $a <=> $b } @include;
			my @include_invlist= (shift @include);
			push @include_invlist, $include_invlist[0] + 1;
			for (my $i= 0; $i <= $#include; $i++) {
				# If the next char is adjacent, extend the span
				if ($include_invlist[-1] == $include[$i]) {
					++$include_invlist[-1];
				} else {
					push @include_invlist, $include[$i], $include[$i]+1;
				}
			}
			push @invlists, \@include_invlist;
		}
		# Repeatedly select the minimum range and add it to the result
		if (!@invlists) {
			@invlists= ( [] );
		}
		elsif (@invlists > 1) {
			my @invlist= ();
			while (@invlists) {
				my ($min_ch, $min_i)= ($invlists[0][0], 0);
				for (my $i= 1; $i < @invlists; $i++) {
					if ($invlists[$i][0] < $min_ch) { $min_ch= $invlists[$i][0]; $min_i= $i; }
				}
				# Check for overlap of this new inclusion range with the previous
				if (@invlist && $invlist[-1] >= $min_ch) {
					pop @invlist;
					shift @{$invlists[$min_i]};
					push @invlist, shift @{$invlists[$min_i]};
				}
				else {
					push @invlist, splice @{$invlists[$min_i]}, 0, 2;
				}
				# If this is the only list remaining, append the rest and done
				if (@invlists == 1) {
					push @invlist, @{$invlists[$min_i]};
					last;
				}
				# If the list is empty now, remove it from consideration
				splice @invlists, $min_i, 1 unless @{$invlists[$min_i]};
				# If the invlist ends with an infinite range now, we are done
				last if 1 & scalar @invlist;
			}
			@invlists= ( \@invlist );
		}
		unshift @{ $invlists[0] }, 0 if $invert;
		return $invlists[0];
	}	
}

=head2 expand_invlist_members

Return an array listing each codepoint in an inversion list.  Note that these are not
characters, just codepoint integers to be passed to C<chr>.

=cut

sub expand_invlist_members {
	my $invlist= shift;
	my @members;
	if (@$invlist > 1) {
		push @members, $invlist->[$_*2] .. ($invlist->[$_*2+1]-1)
			for 0 .. (($#$invlist-1)>>1);
	}
	# an odd number of elements means the list ends with an "include-all"
	push @members, $invlist->[-1] .. 0x10FFFF
		if 1 & @$invlist;
	return \@members;
}

=head2 create_invlist_index

Returns an array that can be used in a binary search to get the Nth element of an
inversion list.

=cut

sub create_invlist_index {
	my $invlist= shift;
	my $total= 0;
	my $i= 0;
	my @index;
	for ($i= 0; $i+1 < @$invlist; $i+= 2) {
		push @index, $total += $invlist->[$i+1] - $invlist->[$i];
	}
	if ($i < @$invlist) { # In the case that the final range is infinite
		push @index, $total += 0x110000 - $invlist->[$i];
	}
	return \@index;
}

=head2 get_invlist_element

Get the Nth element of an inversion list, using the supplied index and a binary search.

=cut

sub get_invlist_element {
	my ($ofs, $invlist, $invlist_index)= @_;
	$ofs += @$invlist_index if $ofs < 0;
	return undef if $ofs >= $invlist_index->[-1] || $ofs < 0;
	my ($min, $max, $mid)= (0, $#$invlist_index);
	while (1) {
		$mid= ($min+$max) >> 1;
		if ($ofs >= $invlist_index->[$mid]) {
			$min= $mid+1
		}
		elsif ($mid > 0 && $ofs < $invlist_index->[$mid-1]) {
			$max= $mid-1
		}
		else {
			$ofs -= $invlist_index->[$mid-1] if $mid > 0;
			return $invlist->[$mid*2] + $ofs;
		}
	}
}

1;
