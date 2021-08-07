package Mock::Data::Charset;
use strict;
use warnings;

=head1 SYNOPSIS

  $mock= Mock::Data->new(['Charset']);
  
  $str= $mock->charset_string({ size => 10 }, 'a-fA-f[:digit:]');
  
  $mock->declare_charset_string_generator($name => $charset_pattern, \%defaults);
  $str= $mock->$name

=head1 DESCRIPTION

This plugin provides generators that select characters from a regex-style charset
notation.  The charset string should be whatever you would normally write within
C<< /[ ... ]/ >> in a regular expression.  (This module does not support 100% of
perl's notations for charsets, but tries pretty hard, including support for C<< \p{} >>
sequences)

=cut

# Plugin main method, which applies plugin to a Mock::Data instance
sub apply_mockdata_plugin {
	my ($class, $mockdata)= @_;
	$mockdata->add_generators({
		charset_string => \&charset,
	});
	return $mockdata->mock_data_subclass('Mock::Data::Charset::Methods');
}

@Mock::Data::Charset::Methods::ISA= ( 'Mock::Data' );
$INC{'Mock/Data/Charset/Methods.pm'}= __FILE__;

*Mock::Data::Charset::Methods::charset_string= *charset;
*Mock::Data::Charset::Methods::declare_charset_string_generator= *declare_charset_generator;

=head1 METHODS

=head2 charset

  $mock->charset( \%options, $charset, $size );

This is a generator that returns a string by pulling random members from a charset.
By default, it returns 8 characters, but you can specify a C<size> or C<max_size> to
control this.

As with all generators, the first argument may be a hashref of named options,
and any other positional arguments supply specific named arguments for convenience.

Options:

=over

=item charset

The perl regex notation of the character set.

=item size

A fixed number of characters to select from the set

=item min_size

For dynamic-length strings, the minimum number of characters to select.

=item max_size

For dynamic-length strings, the maximum number of characters to select.

=back

=cut

sub charset {
	my $mock= shift;
	my %opts= ref $_[0] eq 'HASH'? %{ shift() } : ();
	$opts{charset}= $_[0] if defined $_[0];
	$opts{size}= $_[1] if defined $_[1];
	defined $opts{charset} or die "charset definition is required";
	my ($invlist, $index)= @{ _charset_info($opts{charset}) }{'invlist','index'};
	my $size= $opts{size};
	unless (defined $size) {
		my $min= $opts{min_size} || 0;
		my $max= $opts{max_size} || $min + 8;
		$size= int(rand($max - $min + 1)) + $min;
	}
	my $ret= '';
	$ret .= chr get_invlist_element(int(rand $index->[-1]), $invlist, $index)
		for 1..$size;
	return $ret;
}

our %_charset_cache;
sub _charset_info {
	my $notation= shift;
	$_charset_cache{$notation} ||= do {
		my $invlist= charset_invlist($notation);
		my $index= create_invlist_index($invlist);
		{ invlist => $invlist, index => $index }
	};
}

=head2 declare_charset_generator

  $mock->declare_charset_generator($name, $charset, \%default_opts);

Create a named generator for the given charset and default options (such as
min_size/max_size)

=cut

sub declare_charset_generator {
	my ($mock, $name, $notation, $default_opts)= @_;
	my ($invlist, $index)= @{ _charset_info($notation) }{'invlist','index'};
	my ($size, $min_size, $max_size)= @{ $default_opts || {} }{'size','min_size','max_size'};
	my $generator= sub {
		my $n;
		if (@_ > 1) {
			if ($_[1] eq 'HASH') {
				$n= defined $_[2]? $_[2]
					: do {
						my %opts= ( %$default_opts, %{$_[1]} );
						my ($size, $min_size, $max_size)= @opts{'size','min_size','max_size'};
						if (defined $size) {
							$n= $size;
						} else {
							$min_size ||= 0;
							$max_size= $min_size + 8 unless defined $max_size;
							$n= int(rand($max_size-$min_size+1)) + $min_size;
						}
					};
			} elsif (defined $_[1]) {
				$n= $_[1];
			} else {
				$n= defined $size? $size : int(rand($max_size-$min_size+1)) + $min_size;
			}
		}
		else {
			$n= defined $size? $size : int(rand($max_size-$min_size+1)) + $min_size;
		}
		my $ret= '';
		$ret .= chr get_invlist_element(int(rand $index->[-1]), $invlist, $index)
			for 1..$n;
		return $ret;
	};
	$mock->merge_generators($name => $generator);
}

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
	o => \&_parse_charset_oct,
	p => \&_parse_charset_classname,
	P => sub { _parse_charset_classname(shift, 1) },
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
	'Any' => [ 0 ],
	'\\N' => [ 0, ord("\n"), 1+ord("\n") ],
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
	/\G( [0-9A-Fa-f]{2} | \{ ([0-9A-Fa-f]+) \} )/gcx
		or die "Invalid hex escape at '".substr($_,pos,10)."'";
	return hex(defined $2? $2 : $1);
}
sub _parse_charset_oct {
	--pos; # The caller ate one of the characters we need to parse
	/\G( 0 | [0-7]{3} | o\{ ([0-7]+) \} ) /gcx
		or die "Invalid octal escape at '".substr($_,pos,10)."'";
	return oct(defined $2? $2 : $1);
}
sub _parse_charset_namedchar {
	require charnames;
	/\G \{ ([^}]+) \} /gcx
#		or die "Invalid named char following \\N at '".substr($_,pos,10)."'";
		and return charnames::vianame($1);
	# Plain "\N" means every character except \n
	push @{ $_[0]{classes} }, '\\N';
	return;
}
sub _parse_charset_classname {
	my ($result, $negate)= @_;
	/\G \{ ([^}]+) \} /gcx
		or die "Invalid class name following \\p at '".substr($_,pos,10)."'";
	push @{$result->{classes}}, ($negate? "^$1" : $1);
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

sub parse_regex {
	my $re= shift;
	return _parse_regex({}) for "$re";
}

our %_regex_syntax_unsupported= (
	'' => {},
);
sub _parse_regex {
	my $flags= shift || {};
	my $expr= [];
	my @or= ( $expr );
	while (1) {
		# begin parenthetical sub-expression?
		if (/\G \( (\?)? /gcx) {
			my $sub_flags= $flags;
			if (defined $1) {
				# leading question mark means regex flags.  This only supports the colon one:
				/\G ( \^ \w* )? : /gcx
					or die "Unsupported regex feature '(?".substr($_,pos,10)."'";
				$sub_flags= { map +( $_ => 1 ), split '', $1 }
					if defined $1;
			}
			my $pos= pos;
			push @$expr, _parse_regex($sub_flags);
			/\G \) /gcx
				or die "Missing end-parenthesee, started at '".substr($_,$pos,10)."'";
		}
		# end sub-expression or next alternation?
		if (/\G ( [|)] ) /gcx) {
			# end of sub-expression, return.
			if (ord $1 == ord ')') {
				# back it up so the caller knows why we exited
				--pos;
				last;
			}
			# else begin next piece of @or
			push @or, ($expr= []);
		}
		# character class?
		elsif (/\G ( \[ | \\w | \\W | \\s | \\S | \\d | \\D | \\N | \. ) /gcx) {
			if (ord $1 == ord '[') {
				push @$expr, _parse_charset();
			}
			elsif (ord $1 == ord '\\') {
				my $callback= $_parse_charset_backslash{substr($1,1)};
				my $charset= { classes => [] };
				$callback->($charset);
				push @$expr, $charset;
			}
			elsif (ord $1 == ord '.') {
				push @$expr, { classes => [ $flags->{s}? 'Any' : '\\N' ] };
			}
			else { ... }
		}
		# repetition?
		elsif (/\G ( \? | \* | \+ | \{ ([0-9]*) (,)? ([0-9]*) \} ) /gcx) {
			my ($min,$max);
			if (ord $1 == ord '?') {
				($min,$max)= (0,1);
			}
			elsif (ord $1 == ord '*') {
				($min,$max)= (0,undef);
			}
			elsif (ord $1 == ord '+') {
				($min,$max)= (1,undef);
			}
			else {
				($min,$max)= ($2,$3);
				$min ||= 0;
			}
			# What came before this?
			if (!@$expr) {
				die "Found quantifier '$1' before anything to quantify at '".substr($_,pos)."'";
			}
			elsif (!ref $expr->[-1]) {
				if (length $expr->[-1] > 1) {
					push @$expr, { expr => [ substr($expr->[-1], -1) ] };
					substr($expr->[-2], -1)= '';
				}
				else {
					$expr->[-1]= { expr => [ $expr->[-1] ] };
				}
			}
			else {
				# If a quantifier is being applied to a thing that already had a quantifier
				#  (such as /X*?/ )
				# this has no effect on the generator
				next
					if defined $expr->[-1]{size}
					|| defined $expr->[-1]{min_size}
					|| defined $expr->[-1]{max_size};
			}
			if (defined $max && $min == $max) {
				$expr->[-1]{size}= $min;
			} else {
				$expr->[-1]{min_size}= $min;
				$expr->[-1]{max_size}= $max if defined $max;
			}
		}
		elsif (/\G (\\)? (.) /gcxs) {
			# Tell users about unsupported features
			die "Unsupported notation: '$1$2'" if $_regex_syntax_unsupported{$1||''}{$2};	
			if ($flags->{i} && (uc $2 ne lc $2)) {
				push @$expr, { chars => [uc $2, lc $2] };
			}
			elsif (@$expr && !ref $expr->[-1]) {
				$expr->[-1] .= $2;
			}
			else {
				push @$expr, $2;
			}
		}
		else {
			last; # end of string
		}
	}
	return @or > 1? { or => \@or }
		: @$expr > 1 || !ref $expr->[0]? { expr => $expr }
		: $expr->[0];
}

1;