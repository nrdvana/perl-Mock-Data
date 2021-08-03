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

sub charset_invlist {
	my ($notation, $max_codepoint)= @_;
	# If the search space is small, it is probably faster to iterate and let perl do the work
	# than to parse the charset.
	my $invlist;
	if (!defined $max_codepoint or $max_codepoint > 1000 or ref $notation) {
		$max_codepoint ||= 0x10FFFF;
		eval {
			my $parse= ref $notation eq 'HASH'? $notation : parse_charset($notation);
			$invlist= _parsed_charset_to_invlist($parse, $max_codepoint);
		} or print "# $@\n";
		return $invlist if defined $invlist;
	}
	return _charset_invlist_brute_force($notation, $max_codepoint);
}

sub _charset_invlist_brute_force {
	my ($notation, $max_codepoint)= @_;
	my $re= qr/[$notation]/;
	my @invlist;
	my $match;
	for (0..$max_codepoint) {
		next unless $match xor (chr($_) =~ $re);
		push @invlist, $_;
		$match= !$match;
	}
	if ($max_codepoint < 0x10FFFF and 1 & @invlist) {
		push @invlist, $max_codepoint+1;
	}
	return \@invlist;
}

=head2 parse_charset

  my $parse_info= parse_charset('\dA-Z_');
  # {
  #   chars   => [ '_' ],
  #   ranges  => [ [ ord("A"), ord("Z") ] ],
  #   classes => [ 'digit' ],
  #   negate  => '',
  # }

This function attempts to parse a perl regex character class the same way perl would,
and records what it found as a list of member C<chars>, array of C<ranges> (pairs of
codepoints), and named character C<classes>.

The result can then be converted to an inversion list using C<charset_invlist>.

=cut

sub parse_charset {
	my $notation= shift;
	$notation .= ']';
	# parse function needs $_ to be the input string
	pos($notation)= 0;
	return _parse_charset() for $notation;
}

our $have_prop_invlist;
our @_backslash_h_invlist= (
  0x09,0x0A, 0x20,0x21, 0xA0,0xA1, 0x1680,0x1681, 0x2000,0x200B, 0x202F,0x2030,
  0x205F,0x2060, 0x3000,0x3001
);
our @_backslash_v_invlist= ( 0x0A,0x0E, 0x85,0x86, 0x2028,0x202A );
our %_parse_charset_backslash= (
	a => ord "\a",
	b => ord "\b",
	c => sub { ... },
	d => sub { push @{$_[0]{classes}}, 'digit'; undef; },
	D => sub { push @{$_[0]{classes}}, '^digit'; undef; },
	e => ord "\e",
	f => ord "\f",
	h => sub { push @{$_[0]{classes}}, '\\h'; undef; },
	H => sub { push @{$_[0]{classes}}, '^\\h'; undef; },
	n => ord "\n",
	N => \&_parse_charset_namedchar,
	p => \&_parse_charset_classname,
	r => ord "\r",
	s => sub { push @{$_[0]{classes}}, 'space'; undef; },
	S => sub { push @{$_[0]{classes}}, '^space'; undef; },
	t => ord "\t",
	v => sub { push @{$_[0]{classes}}, '\\v'; undef; },
	V => sub { push @{$_[0]{classes}}, '^\\v'; undef; },
	w => sub { push @{$_[0]{classes}}, 'word'; undef; },
	W => sub { push @{$_[0]{classes}}, '^word'; undef; },
	x => \&_parse_charset_hex,
	0 => \&_parse_charset_oct,
	1 => \&_parse_charset_oct,
	2 => \&_parse_charset_oct,
	3 => \&_parse_charset_oct,
	4 => \&_parse_charset_oct,
	5 => \&_parse_charset_oct,
	6 => \&_parse_charset_oct,
	7 => \&_parse_charset_oct,
	8 => \&_parse_charset_oct,
	9 => \&_parse_charset_oct,
);
our %_class_invlist_cache= (
	'\\h' => \@_backslash_h_invlist,
	'\\v' => \@_backslash_v_invlist,
);
sub _class_invlist {
	my $class= shift;
	return _class_invlist(substr($class,1))
		if ord $class == ord '^';
	return $_class_invlist_cache{$class} ||= do {
		$have_prop_invlist= do { require Unicode::UCD; !!Unicode::UCD->can('prop_invlist') }
			unless defined $have_prop_invlist;
		return $have_prop_invlist? [ Unicode::UCD::prop_invlist($class) ]
			: _charset_invlist_brute_force("\\p{$class}", 0x10FFFF);
	};
}
sub _parse_charset_hex {
	/\G( [0-9A-Za-z] [0-9A-Za-z]? )/gcx
		or die "Unexpected hex escape at '".substr($_,pos,10)."'";
	return hex $1;
}
sub _parse_charset_oct {
	/\G( [0-7]{1,3} ) /gcx
		or die "Invalid octal escape at '".substr($_,pos,10)."'";
	return oct $1;
}
sub _parse_charset_namedchar {
	require charnames;
	/\G \{ ([^}]+) \} /gcx
		or die "Invalid named char following \\N at '".substr($_,pos,10)."'";
	return charnames::vianame($1);
}
sub _parse_charset_classname {
	/\G \{ ([^}]+) \} /gcx
		or die "Invalid class name following \\p at '".substr($_,pos,10)."'";
	push @{$_[0]{classes}}, $1;
	undef
}

sub _parse_charset {
	# argument is in $_, starting from pos($_)
	my %parse;
	my @range;
	$parse{chars}= \my @chars;
	$parse{ranges}= \my @ranges;
	$parse{classes}= \my @classes;
	$parse{negate}= /\G \^ /gcx;
	if (/\G]/gc) { push @chars, ord ']' }
	while (1) {
		my $cp; # literal codepoint to be added
		# Check for special cases
		if (/\G ( \\ | - | \[: | \] ) /gcx) {
			if ($1 eq '\\') {
				/\G(.)/gc or die "Unexpected end of input";
				$cp= $_parse_charset_backslash{$1} || ord $1;
				$cp= $cp->(\%parse)
					if ref $cp;
			}
			elsif ($1 eq '-') {
				if (@range == 1) {
					push @range, ord '-';
					next;
				}
				else {
					$cp= ord '-';
				}
			}
			elsif ($1 eq '[:') {
				/\G ( [^:]+ ) :] /gcx
					or die "Invalid character class at '".substr($_,pos,10)."'";
				push @classes, $1;
			}
			else {
				last; # $1 eq ']';
			}
		}
		else {
			/\G(.)/gc or die "Unexpected end of input";
			$cp= ord $1;
		}
		# If no single character was found, any range-in-progress needs converted to
		# charcters
		if (!defined $cp) {
			push @chars, @range;
			@range= ();
		}
		# At this point, $cp will contain the next ordinal of the character to include,
		# but it might also be starting or finishing a range.
		elsif (@range == 1) {
			push @chars, $range[0];
			$range[0]= $cp;
		}
		elsif (@range == 2) {
			push @ranges, [ $range[0], $cp ];
			@range= ();
		}
		else {
			push @range, $cp;
		}
		#printf "# pos %d  cp %d  range %s %s  include %s\n", pos $_, $cp, $range[0] // '(null)', $range[1] // '(null)', join(',', @include);
	}
	push @chars, @range;
	@chars= sort { $a <=> $b } @chars;
	return \%parse;
}

sub _parsed_charset_to_invlist {
	my ($parse, $max_codepoint)= @_;
	my @invlists;
	# convert the character list into an inversion list
	if ($parse->{chars} && @{$parse->{chars}}) {
		my @chars= sort { $a <=> $b } @{ $parse->{chars} };
		my @invlist= (shift @chars);
		push @invlist, $invlist[0] + 1;
		for (my $i= 0; $i <= $#chars; $i++) {
			# If the next char is adjacent, extend the span
			if ($invlist[-1] == $chars[$i]) {
				++$invlist[-1];
			} else {
				push @invlist, $chars[$i], $chars[$i]+1;
			}
		}
		push @invlists, \@invlist;
	}
	# Each range is an inversion list already
	if ($parse->{ranges}) {
		for (@{ $parse->{ranges} }) {
			# Try to combine the range with the most recent inversion list, if possible,
			if (@invlists && $invlists[-1][-1] < $_->[0]) {
				push @{ $invlists[-1] }, $_->[0], $_->[1]+1;
			} elsif (@invlists && $invlists[-1][0] > $_->[1]+1) {
				unshift @{ $invlists[-1] }, $_->[0], $_->[1]+1;
			} else {
				# else just start a new inversion list
				push @invlists, [ $_->[0], $_->[1]+1 ]
			}
		}
	}
	# Convert each character class to an inversion list.
	if ($parse->{classes}) {
		push @invlists, _class_invlist($_)
			for @{ $parse->{classes} };
	}
	my $invlist= _combine_invlists(\@invlists, $max_codepoint);
	# Perform negation of inversion list by either starting at char 0 or removing char 0
	if ($parse->{negate}) {
		if ($invlist->[0]) { unshift @$invlist, 0 }
		else { shift @$invlist; }
	}
	return $invlist;
}

sub _combine_invlists {
	my ($invlists, $max_codepoint)= @_;
	return [] unless $invlists && @$invlists;
	my @combined= ();
	# Repeatedly select the minimum range among the input lists and add it to the result
	while (@$invlists) {
		my ($min_ch, $min_i)= ($invlists->[0][0], 0);
		# Find which inversion list contains the lowest range
		for (my $i= 1; $i < @$invlists; $i++) {
			if ($invlists->[$i][0] < $min_ch) {
				$min_ch= $invlists->[$i][0];
				$min_i= $i;
			}
		}
		last if $min_ch > $max_codepoint;
		# Check for overlap of this new inclusion range with the previous
		if (@combined && $combined[-1] >= $min_ch) {
			# they overlap, so just replace the end-codepoint of the range
			pop @combined;
			shift @{$invlists->[$min_i]};
			push @combined, shift @{$invlists->[$min_i]};
		}
		else {
			# else, simply append the range
			push @combined, splice @{$invlists->[$min_i]}, 0, 2;
		}
		# If this is the only list remaining, append the rest and done
		if (@$invlists == 1) {
			push @combined, @{$invlists->[$min_i]};
			last;
		}
		# If the list is empty now, remove it from consideration
		splice @$invlists, $min_i, 1 unless @{$invlists->[$min_i]};
		# If the invlist ends with an infinite range now, we are done
		last if 1 & scalar @combined;
	}
	while ($combined[-1] > $max_codepoint) {
		pop @combined;
	}
	# If the list ends with inclusion, and the max_codepoint is less than unicode max,
	# end the list with it.
	if (1 & @combined and $max_codepoint < 0x10FFFF) {
		push @combined, $max_codepoint+1;
	}
	return \@combined;
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
