package Mock::Data::Generator::Charset;
use strict;
use warnings;
use Carp ();

=head1 SYNOPSIS

  # Export a handy alias for the constructor
  use Mock::Data::Generator::Charset 'charset';
  
  # Use perl's regex notation for [] charsets
  my $charset = charset('A-Za-z');
          ... = charset('\p{alpha}\s\d');
          ... = charset(class => 'digit');
          ... = charset(range => ['a','z']);
          ... = charset(chars => ['a','e','i','o','u']);
  
  # Test membership
  charset('a-z')->contains('a') # true
  charset('a-z')->count         # 26
  charset('\w')->count          # 
  charset('\w')->count('ascii') # 
  
  # Iterate
  my $charset= charset('a-z');
  for (0 .. $charset->count-1) {
    my $ch= $charset->get_member($_)
  }
  # this one can be very expensive if the set is large:
  for ($charset->members->@*) { ... }
  
  # Generate random strings
  my $str= $charset->generate($mockdata, 10); # 10 random chars from this charset
      ...= $charset->generate($mockdata, { min_codepoint => 1, max_codepoint => 127 }, 10);
      ...= $charset->generate($mockdata, { min_size => 5, max_size => 10 });

=head1 DESCRIPTION

This generator is optimized for holding sets of Unicode characters.  It behaves just like
the L<Mock::Data::Generator::Set|Set> generator but it also lets you inspect the member
codepoints, iterate the codepoints, and constrain the range of codepoints when generating
strings.

=head1 CONSTRUCTOR

  $charset= Mock::Data::Generator::Charset->new( %options );
  $charset= charset( %options );
  $charset= charset( $regex_spec );

The constructor takes any of the following options:

=over

=item chars

An arrayref of literal character values to include in the set

=item ranges

An arrayref holding start/end pairs of characters, optionally with inner arrayrefs for each
start/end pair.

=item classes

An arrayref of character class names recognized by perl (such as Posix or Unicode classes)

=back

The constructor may also be given defaults for any of the options of the L</generate|generator>
(see below).

For convenience, you may export the L<Mock::Data::Util/charset> which calls this constructor.

=cut

sub new {
	my $class= shift;
	# make the common case fast
	return bless { notation => $_[0] }, $class
		if @_ == 1 && !ref $_[0];

	my %self= @_ != 1? @_ : %{$_[0]};

	# Look for fields from the parser
	my %parse;
	$parse{classes}= delete $self{classes} if defined $self{classes};
	$parse{codepoints}= delete $self{codepoints} if defined $self{codepoints};
	$parse{codepoint_ranges}= delete $self{codepoint_ranges} if defined $self{codepoint_ranges};
	$parse{negate}= delete $self{negate} if defined $self{negate};
	if (defined $self{chars}) {
		push @{$parse{codepoints}}, map ord, @{$self{chars}};
		delete $self{chars};
	}
	if (defined $self{ranges}) {
		push @{$parse{codepoint_ranges}},
			map +( ref $_? ( ord $_->[0], ord $_->[1] ) : ord ),
				@{$self{ranges}};
		delete $self{ranges};
	}
	if (keys %parse) {
		$self{_parse}= \%parse;
	}

	# At least one of members, member_invlist, notation, or _parse must be specified
	Carp::croak "Require at least one attribute of: members, member_invlist, notation, classes,"
		. " codepoints, codepoint_ranges, ranges"
		unless $self{members} || $self{member_invlist} || $self{notation} || $self{_parse};
	
	return bless \%self, $class;
}

sub _parse {
	# If the '_parse' wasn't initialized, it can be derived from members or member_invlist or notation
	$_[0]{_parse} || do {
		my $self= shift;
		if (defined $self->{notation}) {
			$self->{_parse}= $self->parse($self->{notation});
		}
		elsif ($self->{members}) {
			$self->{_parse}{codepoints}= [ map ord, @{$self->{members}} ];
		}
		elsif (my $inv= $self->{member_invlist}) {
			my $i;
			for ($i= 0; $i < $#$inv; $i+= 2) {
				if ($inv->[$i] + 1 == $inv->[$i+1]) { push @{$self->{_parse}{codepoints}}, $inv->[$i] }
				else { push @{$self->{_parse}{codepoint_ranges}}, $inv->[$i], $inv->[$i+1] - 1; }
			}
			if ($i == $#$inv) {
				push @{$self->{_parse}{codepoint_ranges}}, $inv->[$i], ($self->max_codepoint || 0x10FFFF);
			}
		}
		else { die "Unhandled lazy-build scenario" }
		$self->{_parse};
	};
}

=head1 ATTRIBUTES

=head2 max_codepoint

Maximum unicode codepoint to be considered.  Read-only.  If you are only interested in a subset
of the Unicode character space, such as ASCII, you can set this to a value like C<0x7F> and
speed up the calculations on the character set.

=cut

sub max_codepoint {
	$_[0]{max_codepoint}
}

=head2 notation

This returns the same string that was passed to the constructor, if you gave the constructor
a regex-notation string instead of more specific attributes.  Else it constructs one from the
attributes. Read-only.

=cut

sub _ord_to_safe_regex_char {
	return chr($_[0]) =~ /[\w]/? chr $_[0]
		: $_[0] <= 0xFF? sprintf('\x%02X',$_[0])
		: sprintf('\x{%X}',$_[0])
}
sub notation {
	$_[0]{notation} //= _deparse($_[0]->_parse);
}

=head2 generate_opts

Default options to pass to L</generate> (and will be combined with an options given to the
function directly).

=cut

sub generate_opts { $_[0]{generate_opts} ||= {} }

=head2 count

The number of members in the set

=cut

sub count {
	$_[0]->_invlist_index->[-1];
}

sub _invlist_index {
	my $self= shift;
	$self->{_invlist_index} ||= _create_invlist_index($self->member_invlist);
}

sub _create_invlist_index {
	my $invlist= shift;
	my $n_spans= (@$invlist + 1) >> 1;
	my @index;
	$#index= $n_spans-1;
	my $total= 0;
	$index[$_]= $total += $invlist->[$_*2+1] - $invlist->[$_*2]
		for 0 .. (@$invlist >> 1)-1;
	if (@$invlist & 1) { # In the case that the final range is infinite
		$index[$n_spans-1]= $total + 0x110000 - $invlist->[-1];
	}
	\@index;
}

=head2 get_member

  my $char= $charset->get_member($offset);

Return the Nth character of the set, starting from 0.  Returns undef for values
greater or equal to L</count>.  You can use negative offsets to index from the
end of the list, like in C<substr>.

=cut

sub get_member {
	_get_invlist_element($_[1], $_[0]->member_invlist, $_[0]->_invlist_index);
}

sub _get_invlist_element {
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

=head2 members

Returns an arrayref of each character in the set.  Try not to use this attribute, as building
it can be very expensive for common sets like C<< [:alpha:] >> (100K members, tens of MB
of RAM).  Use L</member_invlist> instead, when possible.

=cut

sub members {
	$_[0]{members} ||= _expand_invlist_members($_[0]->member_invlist);
}

sub _expand_invlist_members {
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

=head2 member_invlist

Return an arrayref holding the "inversion list" describing the members of this set.  An
inversion list stores the first codepoint belonging to the set, followed by the next higher
codepoint which does not belong to the set, followed by the next that does, etc.  This data
structure allows for efficient negation/inversion of the list.

You may write a new value to this attribute, but not modify the existing array.

=cut

sub member_invlist {
	if (@_ > 1) {
		$_[0]{member_invlist}= $_[1]; 
		delete $_[0]{_invlist_index};
	}
	$_[0]{member_invlist} //= _build_member_invlist(@_);
}

sub _build_member_invlist {
	my $self= shift;
	my $max_codepoint= $self->max_codepoint;
	# If the search space is small, and there is already a regex notation, it is probably faster
	# to iterate and let perl do the work than to parse the charset.
	my $invlist;
	if (!defined $max_codepoint || $max_codepoint > 1000 || !defined $self->{notation}) {
		$max_codepoint ||= 0x10FFFF;
		$invlist= eval {
			_parsed_charset_to_invlist($self->_parse, $max_codepoint);
		};
	}
	$invlist ||= _charset_invlist_brute_force($self->notation, $max_codepoint);
	# If a user writes to the invlist, it will become out of sync with the Index,
	# leading to confusing bugs.
	if (Internals->can('SvREADONLY')) {
		Internals::SvREADONLY($_,1) for @$invlist;
		Internals::SvREADONLY(@$invlist,1);
	}
	return $invlist;
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
	# If an "infinite" range would be returned, but the user set a maximum codepoint,
	# list the max codepoint as the end of the invlist.
	if ($max_codepoint < 0x10FFFF and 1 & @invlist) {
		push @invlist, $max_codepoint+1;
	}
	return \@invlist;
}

sub _parsed_charset_to_invlist {
	my ($parse, $max_codepoint)= @_;
	my @invlists;
	# convert the character list into an inversion list
	if (defined (my $cp= $parse->{codepoints})) {
		my @chars= sort { $a <=> $b } @$cp;
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
	if (my $r= $parse->{codepoint_ranges}) {
		for (my $i= 0; $i < (@$r >> 1); $i++) {
			my ($start, $limit)= ($r->[$i*2], $r->[$i*2+1]+1);
			# Try to combine the range with the most recent inversion list, if possible,
			if (@invlists && $invlists[-1][-1] < $start) {
				push @{ $invlists[-1] }, $start, $limit;
			} elsif (@invlists && $invlists[-1][0] > $limit) {
				unshift @{ $invlists[-1] }, $start, $limit;
			} else {
				# else just start a new inversion list
				push @invlists, [ $start, $limit ]
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

=head1 METHODS

=head2 generate

=over

=item min_codepoint

Clamp the set to a minimum codepoint, like C<1> or C<32>.

=item max_codepoint

Clamp the set to a maximum codepoint, like C<127>.

=item size

Specify the number of characters to return in the string.  This is a shortbut for setting both
C<min_size> and C<max_size>.

=item min_size

Specify the minimum number of characters to return in the string.  The number will be random
between the minimum and maximum.

=item max_size

Specify the maximum number of characters to return in the string.  The number will be random
between the minimum and maximum.

=back

=head2 compile

Return a plain coderef that invokes L</generate> on this object.

=cut

sub generate {
	my ($self, $mock)= (shift, shift);
	my %opts= ref $_[0] eq 'HASH'? %{ shift() } : ();
	my $size= shift // $opts{size};
	unless (defined $size) {
		my $min_size= $opts{min_size} // $self->generate_opts->{size} // $self->generate_opts->{min_size} // 1;
		my $max_size= $opts{max_size} // $self->generate_opts->{size} // $self->generate_opts->{max_size} // 8;
		$size= $min_size + int rand($max_size - $min_size + 1);
	}
	my $invlist= $self->member_invlist;
	my $index= $self->_invlist_index;
	my $ret= '';
	$ret .= chr _get_invlist_element(int(rand $index->[-1]), $invlist, $index)
		for 1..$size;
	return $ret;
}

sub compile {
	my $self= shift;
	my $invlist= $self->inversion_list;
	my $index= $self->_inversion_list_index;
	my $default_opt= $self->generate_opts;
	my $default_size= $default_opt->{size};
	my $default_min= $default_size // $default_opt->{min_size} // 1;
	my $default_max= $default_size // $default_opt->{max_size} // 8;
	return sub {
		# my ($mockdata, \%options, $size)= @_;
		my $size;
		if (@_ > 1) {
			# If a new hashref of options is given, merge those with the defaults
			if ($_[1] eq 'HASH') {
				$size= defined $_[2]? $_[2]
					: defined $_[1]{size}? $_[1]{size}
					: do {
						my $min= $_[1]{min_size} // $default_min;
						my $max= $_[1]{max_size} // $default_max;
						$size= $min + int rand($max - $min + 1);
					};
			# else a single scalar option is is $size
			} elsif (defined $_[1]) {
				$size= $_[1];
			}
		} else {
			$size= $default_size // ($default_min + int rand($default_max - $default_min + 1));
		}
		my $ret= '';
		$ret .= chr _get_invlist_element(int(rand $index->[-1]), $invlist, $index)
			for 1..$size;
		return $ret;
	};
}

=head2 parse

  my $parse_info= Mock::Data::Generator::Charset->parse('\dA-Z_');
  # {
  #   codepoints        => [ ord '_' ],
  #   codepoint_ranges  => [ ord "A", ord "Z" ],
  #   classes           => [ 'digit' ],
  # }

This is a class method that accepts a Perl-regex-notation string for a charset and returns
a hashref of the arguments that should be passed to the constructor.

This dies if it encounters a syntax error or any Perl feature that wasn't implemented.

=cut

sub parse {
	my ($self, $notation)= @_;
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
	$parse{codepoints}= \my @chars;
	$parse{negate}= 1 if /\G \^ /gcx;
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
				push @{$parse{classes}}, $1;
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
			push @{$parse{codepoint_ranges}}, $range[0], $cp;
			@range= ();
		}
		else {
			push @range, $cp;
		}
		#printf "# pos %d  cp %d  range %s %s  include %s\n", pos $_, $cp, $range[0] // '(null)', $range[1] // '(null)', join(',', @include);
	}
	push @chars, @range;
	if (@chars) {
		@chars= sort { $a <=> $b } @chars;
	} else {
		delete $parse{codepoints};
	}
	return \%parse;
}
sub _deparse_charset {
	my $parse= shift;
	my $str= '';
	if (my $cp= $parse->{codepoints}) {
		$str .= _ord_to_safe_regex_char($_)
			for @$cp;
	}
	if (my $r= $parse->{codepoint_ranges}) {
		for (my $i= 0; $i < (@$r << 1); $i++) {
			$str .= _ord_to_safe_regex_char($r->[$i*2]) . '-' . _ord_to_safe_regex_char($r->[$i*2+1]);
		}
	}
	if (my $cl= $parse->{classes}) {
		# TODO: reverse conversions to \h \v etc.
		$str .= '\p{' . $cl . '}';
	}
	return $str;
}

1;
