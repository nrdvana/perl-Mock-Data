package Mock::Data::Regex;
use strict;
use warnings;
use Mock::Data::Charset;
use Mock::Data::Util qw( _parse_context _escape_str );
require Carp;
require Scalar::Util;
require List::Util;
require Hash::Util;
require Mock::Data::Generator;
our @ISA= ( 'Mock::Data::Generator' );

# ABSTRACT: Generator that uses a Regex as a template to generate strings
# VERSION

=head1 SYNOPSIS

  # Automatically used when you give a Regexp ref to Mock::Data
  my $mock= Mock::Data->new(generators => { word => qr/\w+/ });
  
  # or use stand-alone
  my $email= Mock::Data::Regex->new( qr/ [-a-z]+\d{0,2} @ [a-z]{2,20} \. (com|net|org) /xa );
  say $email->generate;  # o25@nskwprtpqlqbeg.org
  
  # define attributes, or override them on demand
  say Mock::Data::Regex->new($regex)->generate($mock, { max_repetition => 50 });
  say Mock::Data::Regex->new(regex => $regex, max_repetition => 50)->generate($mock);
  
  # constrain the characters selected
  my $any= Mock::Data::Regex->new(qr/.+/);
  say $any->generate($mock, { min_codepoint => 0x20, max_codepoint => 0xFFFF });
  
  # surround generated regex-match with un-matched prefix/suffix
  say $email->generate($mock, { prefix => q{<a href="mailto:}, suffix => q{">Contact</a>} });

=head1 DESCRIPTION

This generator creates strings that match a user-supplied regular expression.

=head1 CONSTRUCTOR

=head2 new

  my $gen= Mock::Data::Regex->new( $regex_ref );
                         ...->new( \%options );
                         ...->new( %options );

The constructor can take a key/value list of attributes, hash of attributes,
or a single argument which is assumed to be a regular expression.

Any attribute may be supplied in C<%options>.  The regular expression must be provided, and
it is parsed immediately to check whether it is supported by this module.  (this module lacks
support for several regex features, such as lookaround assertions and backreferences)

=cut

sub new {
	my $class= shift;
	my %self= @_ == 1 && (!ref $_[0] || ref $_[0] eq 'Regexp')? ( regex => $_[0] )
		: @_ == 1? %{$_[0]}
		: @_;

	# If called on an object, carry over some settings
	if (ref $class) {
		%self= ( %$class, %self );
		# Make sure we didn't copy a regex without a matching regex_parse_tree, or vice versa
		if ($self{regex} == $class->{regex} xor $self{regex_parse_tree} == $class->{regex_parse_tree}) {
			delete $self{regex_parse_tree} if $self{regex_parse_tree} == $class->{regex_parse_tree};
			delete $self{regex} if $self{regex} == $class->{regex};
		}
		$class= ref $class;
	}

	defined $self{regex} or Carp::croak "Attribute 'regex' is required";
	$self{regex}= qr/$self{regex}/ unless ref $self{regex} eq 'Regexp';
	# Must be parsed eventually, so might as well do it now and see the errors right away
	$self{regex_parse_tree} ||= $class->parse($self{regex});
	$self{max_codepoint} //= 0x7F if $self{regex_parse_tree}->flags->{a};

	$self{prefix} //= Mock::Data::Util::coerce_generator($self{prefix}) if defined $self{prefix};
	$self{suffix} //= Mock::Data::Util::coerce_generator($self{suffix}) if defined $self{suffix};

	return bless \%self, $class;
}

=head1 ATTRIBUTES

=head2 regex

The regular expression this generator is matching.  This will always be a regex-ref,
even if you gave a string to the constructor.

=head2 regex_parse_tree

A data structure describing the regular expression.  WARNING: The API of this data structure
may change in future versions.

=cut

sub regex { $_[0]{regex} }

sub regex_parse_tree { $_[0]{regex_parse_tree} }

=head2 min_codepoint

The minimum codepoint to be considered when processing the regular expression or generating
strings from it.  You might choose to set this to i.e. 0x20 to avoid generating control
characters.  This only affects selection from character sets; literal control characters in
the pattern will still be returned.

=head2 max_codepoint

The maximum codepoint to be considered when processing the regular expression or generating
strings from it.  Setting this to a low value (like 127 for ASCII) can speed up the algorithm
in many cases.  This is set to 127 automatically if the L</regex> has the C<< /a >> flag.

=cut

sub min_codepoint {
	$_[0]{min_codepoint}
}

sub max_codepoint { $_[0]{max_codepoint} }

=head2 max_repetition

  max_repetition => '+8',
  max_repetition => 10,

Whenever a regex has an un-bounded repetition, this determines the upper bound on the random
number of repetitions.  Set this to a plain number to specify an absolute maximum, or string
with leading plus sign (C<< "+$n" >>) to specify a maximum relative to the minimum.  The
default is C<< "+8" >>.

=cut

sub max_repetition { $_[0]{max_repetition} || '+8' }

=head2 prefix

  ->new(regex => qr/foo/,   prefix => '_')->generate # returns "_foo"
  ->new(regex => qr/^foo/,  prefix => '_')->generate # returns "foo"
  ->new(regex => qr/^foo/m, prefix => '_')->generate # returns "_\nfoo"

A generator or template to add to the beginning of the output whenever the regex is not
anchored at the start or is multi-line.  It will be joined to the output with a "\n" if the
regex is multi-line and anchored from '^'.

=head2 suffix

  ->new(regex => qr/foo/,   suffix => '_')->generate # returns "foo_"
  ->new(regex => qr/foo$/,  suffix => '_')->generate # returns "foo"
  ->new(regex => qr/foo$/m, suffix => '_')->generate # returns "foo\n_"

A generator or template to add to the end of the output whenever the regex is not anchored
at the end.

=cut

sub prefix {
	if (@_ > 1) {
		$_[0]{prefix}= Mock::Data::Util::coerce_generator($_[1]);
	}
	$_[0]{prefix} 
}

sub suffix {
	if (@_ > 1) {
		$_[0]{suffix}= Mock::Data::Util::coerce_generator($_[1]);
	}
	$_[0]{suffix}
}

=head1 METHODS

=head2 generate

  my $str= $generator->generate($mockdata, \%options);

Return a string matching the regular expression.  The C<%options> may override the following
attributes: L</min_codepoint>, L</max_codepoint>, L</max_repetitions>, L</prefix>, L</suffix>.

=cut

sub generate {
	my ($self, $mockdata)= (shift,shift);
	my %opts= ref $_[0] eq 'HASH'? %{$_[0]} : ();
	$opts{max_codepoint} //= $self->max_codepoint;
	$opts{min_codepoint} //= $self->min_codepoint;
	$opts{max_repetition} //= $self->max_repetition;
	my $out= $self->_str_builder($mockdata, \%opts);
	$self->regex_parse_tree->generate($out)
		# is the string allowed to end here?  Requirement of '' is generated by $ and \Z
		&& (!$out->next_req || (grep $_ eq '', @{ $out->next_req }))
		or Carp::croak "Regex assertions could not be met (such as '^' or '\$').  Final attempt was: \""._escape_str($out->str)."\"";
	my $prefix= $opts{prefix} // $self->{prefix};
	my $suffix= $opts{suffix} // $self->{suffix};
	return $out->str unless defined $prefix || defined $suffix;

	my $str= $out->str;
	# A prefix can only be added if there was not a beginning-of-string assertion, or if
	# it was a ^/m assertion (flagged as "LF")
	if ($prefix && (!$out->start || $out->start eq 'LF')) {
		my $p= Mock::Data::Util::coerce_generator($prefix)->generate($mockdata);
		$p .= "\n" if $out->start;
		$str= $p . $str;
	}
	# A suffix can only be added if there was not an end-of-string assertion, or if
	# the next assertion allows "\n" and there is no assertion after that.
	if ($suffix && (!$out->next_req || (grep $_ eq "\n", @{ $out->next_req }) && !$out->require->[1])) {
		$str .= "\n" if $out->next_req;
		$str .= Mock::Data::Util::coerce_generator($suffix)->generate($mockdata);
	}
	return $str;
}

=head2 compile

Return a generator coderef that calls L</generate> on this object.

=head2 parse

Parse a regular expression, returning a parse tree describing it.  This can be called as a
class method.

=head2 get_charset

If the regular expression is nothing more than a charset (or repetition of one charset) this
returns that charset.  If the regular expression is more complicated than a simple charset,
this returns C<undef>.

=cut

sub parse {
	my ($self, $regex)= @_;
	return $self->_parse_regex({}) for "$regex";
}

sub get_charset {
	my $self= shift;
	my $p= $self->regex_parse_tree->pattern;
	return Scalar::Util::blessed($p) && $p->isa('Mock::Data::Charset')? $p : undef;
}

our %_regex_syntax_unsupported= (
	'' => { map { $_ => 1 } qw( $ ) },
	'\\' => { map { $_ => 1 } qw( B b A Z z G g K k ) },
);
our %_parse_regex_backslash= (
	map +( $_ => $Mock::Data::Charset::_parse_charset_backslash{$_} ),
		qw( a b c e f n N o r t x 0 1 2 3 4 5 6 7 8 9 )
);
sub _parse_regex {
	my $self= shift;
	my $flags= shift || {};
	my $expr= [];
	my @or;
	while (1) {
		# begin parenthetical sub-expression?
		if (/\G \( (\?)? /gcx) {
			my $sub_flags= $flags;
			if (defined $1) {
				# leading question mark means regex flags.  This only supports the ^...: one:
				if (/\G \^ ( \w* ) : /gcx) {
					$sub_flags= {};
					++$sub_flags->{$_} for split '', $1;
				} elsif ($] < 5.020 and /\G (\w*)-\w* : /gcx) {
					$sub_flags= {};
					++$sub_flags->{$_} for split '', $1;
				} else {
					Carp::croak("Unsupported regex feature '(?".substr($_,pos,1)."'");
				}
			}
			my $pos= pos;
			push @$expr, $self->_parse_regex($sub_flags);
			/\G \) /gcx
				or die "Missing end-parenthesee, started at '"._parse_context($pos)."'";
		}
		# end sub-expression or next alternation?
		if (/\G ( [|)] ) /gcx) {
			# end of sub-expression, return.
			if ($1 eq ')') {
				# back it up so the caller knows why we exited
				--pos;
				last;
			}
			# else begin next piece of @or
			push @or, $self->_node($expr, $flags);
			$expr= [];
		}
		# character class?
		elsif (/\G ( \[ | \\w | \\W | \\s | \\S | \\d | \\D | \\N | \\Z | \. | \^ | \$ ) /gcx) {
			if ($1 eq '[') {
				# parse function continues to operate on $_ at pos()
				my $parse= Mock::Data::Charset::_parse_charset($flags);
				push @$expr, $self->_charset_node($parse, $flags);
			}
			elsif (ord $1 == ord '\\') {
				if ($1 eq "\\Z") {
					push @$expr, $self->_assertion_node(end => 1, flags => $flags);
				}
				else {
					push @$expr, $self->_charset_node(notation => $1, $flags);
				}
			}
			elsif ($1 eq '.') {
				push @$expr, $self->_charset_node(classes => [ $flags->{s}? 'Any' : '\\N' ], $flags);
			}
			elsif ($1 eq '$') {
				push @$expr, $self->_assertion_node(end => ($flags->{m}? 'LF' : 'FinalLF'), flags => $flags);
			}
			elsif ($1 eq '^') {
				push @$expr, $self->_assertion_node(start => ($flags->{m}? 'LF' : 1 ), flags => $flags);
			}
		}
		# repetition?
		elsif (/\G ( \? | \* \?? | \+ \?? | \{ ([0-9]+)? (,)? ([0-9]+)? \} ) /gcx) {
			my @rep;
			if ($1 eq '?') {
				@rep= (0,1);
			}
			elsif (ord $1 == ord '*') {
				@rep= (0);
			}
			elsif (ord $1 == ord '+') {
				@rep= (1);
			}
			else {
				@rep= $3? ($2||0,$4) : ($2||0,$2);
			}
			# What came before this?
			if (!@$expr) {
				die "Found quantifier '$1' before anything to quantify at "._parse_context;
			}
			elsif (!ref $expr->[-1]) {
				# If the string is composed of more than one character, split the final one
				# into its own node so that it can have a repetition applied to it.
				if (length $expr->[-1] > 1) {
					push @$expr, $self->_node([ substr($expr->[-1], -1) ], $flags);
					substr($expr->[-2], -1)= '';
				}
				# else its one character, wrap it in a node
				else {
					$expr->[-1]= $self->_node([ $expr->[-1] ], $flags);
				}
			}
			$expr->[-1]->repetition(\@rep)
		}
		elsif ($flags->{x} && /\G ( \s | [#].* ) /gcx) {
			# ignore whitespace and comments under /x mode
		}
		elsif (/\G (\\)? (.) /gcxs) {
			# Tell users about unsupported features
			die "Unsupported notation: '$1$2'" if $_regex_syntax_unsupported{$1||''}{$2};
			my $ch;
			if ($1 && defined (my $equiv= $_parse_regex_backslash{$2})) {
				$ch= chr(ref $equiv? $equiv->() : $equiv);
			} else {
				$ch= $2;
			}
			if ($flags->{i} && (uc $ch ne lc $ch)) {
				push @$expr, $self->_charset_node(chars => [uc $ch, lc $ch], $flags);
			}
			elsif (@$expr && !ref $expr->[-1]) {
				$expr->[-1] .= $ch;
			}
			else {
				push @$expr, $ch;
			}
		}
		else {
			last; # end of string
		}
	}
	return @or? do { push @or, $self->_node($expr, $flags) if @$expr; $self->_or_node(\@or, $flags) }
		: (@$expr > 1 || !ref $expr->[0])? $self->_node($expr, $flags)
		: $expr->[0];
}

#----------------------------------
# Factory Functions for Parse Nodes

sub _node {
	my ($self, $pattern, $flags)= @_;
	Mock::Data::Regex::ParseNode->new({ pattern => $pattern, flags => $flags });
}
sub _or_node {
	my ($self, $or_list, $flags)= @_;
	Mock::Data::Regex::ParseNode::Or->new({ pattern => $or_list, flags => $flags });
}
sub _charset_node {
	my $self= shift;
	my $flags= pop;
	Mock::Data::Regex::ParseNode::Charset->new({
		pattern => @_ > 1? { @_ } : shift,
		flags => $flags
	});
}
sub _assertion_node {
	my $self= shift;
	Mock::Data::Regex::ParseNode::Assertion->new({ @_ });
}
sub _str_builder {
	my ($self, $mockdata, $opts)= @_;
	Mock::Data::Regex::StrBuilder->new({
		mockdata => $mockdata,
		generator => $self,
		opts => $opts,
	});
}

sub _fake_inc {
	(my $pkg= caller) =~ s,::,/,g;
	$INC{$pkg.'.pm'}= $INC{'Mock/Data/Generator/Regex.pm'};
}

# ------------------------------ Regex Parse Node -------------------------------------
# The regular parse nodes hold a "pattern" which is an arrayref of literal strings
# or nested parse nodes.  It supports a "repetition" flag to handle min/max repetitions
# of the node as a whole.
# Other subclasses are used to handle OR-lists, charsets, and zero-width assertions.

package # Do not index
  Mock::Data::Regex::ParseNode;
Mock::Data::Regex::_fake_inc();

sub new { bless $_[1], $_[0] }

sub flags { $_[0]{flags} }
sub repetition {
	if (@_ > 1) {
		# If a quantifier is being applied to a thing that already had a quantifier
		#  (such as /(X*){2}/ )
		# multiply them
		my $val= $_[1];
		if (my $rep= $_[0]{repetition}) {
			$rep->[$_]= (defined $rep->[$_] && defined $val->[$_]? $rep->[$_] * $val->[$_] : undef)
				for 0, 1;
		}
		else {
			$_[0]{repetition}= $_[1];
		}
	}
	return $_[0]{repetition}
}
sub min_repetition {
	$_[0]{repetition}? $_[0]{repetition}[0] : 1
}
sub max_repetition {
	$_[0]{repetition}? $_[0]{repetition}[1] : 1
}
sub pattern { $_[0]{pattern} }
sub generate {
	my ($self, $out)= @_;
	if (my $rep= $self->repetition) {
		my ($min, $n)= ($rep->[0], $out->_random_rep_count($rep));
		for (1 .. $n) {
			my $origin= $_ > $min? $out->mark : undef;
			# Plain nodes expect the pattern to be an arrayref where each item is a parse node or a literal
			my $success= 1;
			for (@{ $self->{pattern} }) {
				$success &&= ref $_? $_->generate($out) : $out->append($_);
			}
			next if $success;
			# This repetition failed, but did we meet the requirement already?
			if ($origin) {
				$out->reset($origin);
				return 1;
			}
			return 0;
		}
	}
	else {
		# Plain nodes expect the pattern to be an arrayref where each item is a parse node or a literal
		for (@{ $self->{pattern} }) {
			return 0 unless ref $_? $_->generate($out) : $out->append($_);
		}
	}
	return 1;
}

# --------------------------------- Regex "OR" Parse Node ----------------------------
# This parse holds a list of options in ->pattern.  It chooses one of the options at
# random, but then can backtrack if inner parse nodes were not able to match.

package # Do not index
  Mock::Data::Regex::ParseNode::Or;
Mock::Data::Regex::_fake_inc();
our @ISA= ('Mock::Data::Regex::ParseNode');

sub generate {
	my ($self, $out)= @_;
	my ($min, $n)= (1,1);
	if (my $rep= $self->{repetition}) {
		$min= $rep->[0];
		$n= $out->_random_rep_count($rep);
	}
	rep: for (1 .. $n) {
		# OR nodes expect the pattern to be an arrayref where each item is an option
		# for what could be appended.  Need to reset the output after each attempt.
		my $origin= $out->mark;
		# Pick one at random.  It will almost always work on the first try, unless the user
		# has anchor constraints in the pattern.
		my $or= $self->pattern;
		my $pick= $or->[ rand scalar @$or ];
		next rep if ref $pick? $pick->generate($out) : $out->append($pick);
		# if it fails, try all the others in random order
		for (List::Util::shuffle(grep { $_ != $pick } @$or)) {
			# reset output
			$out->reset($origin);
			# append something new
			next rep if ref $_? $_->generate($out) : $out->append($_);
		}
		# None of the options succeeded.  Did we get enough reps already?
		if ($_ > $min) {
			$out->reset($origin);
			return 1;
		}
		return 0;
	}
	return 1;
}

# -------------------------------- Regex Charset Parse Node ---------------------------
# This node's ->pattern is an instance of Charset.  It returns one character
# from the set, but also has an optimized handling of the ->repetition flag that generates
# multiple characters at once.

package # Do not index
  Mock::Data::Regex::ParseNode::Charset;
Mock::Data::Regex::_fake_inc();
our @ISA= ('Mock::Data::Regex::ParseNode');

sub new {
	my ($class, $self)= @_;
	if (ref $self->{pattern} eq 'HASH') {
		$self->{pattern}{max_codepoint}= 0x7F if $self->{flags}{a};
		$self->{pattern}= Mock::Data::Util::charset($self->{pattern});
	}
	bless $self, $class;
}

sub generate {
	my ($self, $out)= @_;
	# Check whether output has a restriction in effect:
	if (my $req= $out->next_req) {
		# pick the first requirement which can be matched by this charset
		for (@$req) {
			if (!ref) {
				# At \Z, can still match if rep count is 0
				return 1 if length == 0 && $self->min_repetition == 0;
				return $out->append($_) if
					length == 1 && $self->pattern->has_member($_)
					or length > 1 && !(grep !$self->pattern->has_member($_), split //);
			}
		}
		return 0;
	}
	my $n= $out->_random_rep_count($self->repetition);
	return $out->append($self->pattern->generate($out->mockdata, $out->opts, $n));
}

# ----------------------------- Regex Assertion Parse Node -------------------------------
# This node doesn't have a ->pattern, and instead holds constraints about what characters
# must occur around the current position.  Right now it only handles '^' and '$' and '\Z'

package # Do not index
  Mock::Data::Regex::ParseNode::Assertion;
Mock::Data::Regex::_fake_inc();
our @ISA= ('Mock::Data::Regex::ParseNode');

sub start { $_[0]{start} }
sub end { $_[0]{end} }
sub generate {
	my ($self, $out)= @_;
	if ($self->{start}) {
		# Previous character must either be start of string or a newline
		length $out->str == 0
			or ($self->{start} eq 'LF' && substr($out->str,-1) eq "\n")
			or return 0;
		# Set flag on entire output if this is the first assertion
		$out->start($self->{start}) if length $out->str == 0 && !$out->start;
	}
	if ($self->{end}) {
		# Next character must be a newline, or end of the output
		# end=1 results from \Z and does not allow the newline
		$out->require(['',"\n"]) unless $self->{end} eq 1;
		# If end=LF, the end of string is no longer mandatory once "\n" has been matched.
		$out->require(['']) unless $self->{end} eq 'LF';
	}
	return 1;
}

# ------------------------ String Builder -----------------------------------
# This class constructs an output string in ->{str}, and also performs checks
# needed by the assertions like ^ and $.  It also has the ability to mark a
# position and then revert to that position, without copying the entire string
# each time.

package # Do not index
  Mock::Data::Regex::StrBuilder;
Mock::Data::Regex::_fake_inc();

sub new {
	my ($class, $self)= @_;
	$self->{str} //= '';
	bless $self, $class;
}

sub mockdata { $_[0]{mockdata} } # Mock::Data instance
sub generator { $_[0]{generator} }
sub opts { $_[0]{opts} }
sub start { $_[0]{start}= $_[1] if @_ > 1; $_[0]{start} }
sub str { $_[0]{str} } # string being built
sub _random_rep_count {
	my ($self, $rep)= @_;
	return 1 unless defined $rep;
	return $rep->[0] + int rand($rep->[1] - $rep->[0] + 1)
		if defined $rep->[1];
	my $range= $self->opts->{max_repetition} // '+8';
	return $rep->[0] + int rand($range+1)
		if ord $range == ord '+';
	$range -= $rep->[0];
	return $range > 0? $rep->[0] + int rand($range+1) : $rep->[0];
}

sub require {
	push @{ $_[0]{require} }, $_[1] if @_ > 1;
	return $_[0]{require};
}
sub next_req {
	return $_[0]{require} && $_[0]{require}[0];
}
sub append {
	my ($self, $content)= @_;
	if (my $req= $self->next_req) {
		# the provided output must be coerced to one of these options, if possible
		# TODO: need new ideas for this code.  Or just give up on the plan of supporting
		# lookaround assertions and focus on a simple implemention of "\n" checks for ^/$
		for (@$req) {
			if (!ref) { # next text must match a literal string.  '' means end-of-string
				if (length && $content eq $_) {
					$self->{str} .= $content;
					shift @{ $self->require }; # requirement complete
					return 1;
				}
			}
			else {
				# TODO: support for "lookaround" assertions, will require regex match
				die "Unimplemented: zero-width lookaround assertions";
			}
		}
		return 0; # no match found for the restriction in effect
	}
	$self->{str} .= $content;
	return 1;
}
sub mark {
	my $self= shift;
	my $len= $self->{lastmark}= length $self->{str};
	my $req= $self->{require};
	return [ \$self->{str}, $len, $req? [ @$req ] : undef, $self->start ];
}
sub reset {
	my ($self, $origin)= @_;
	# If the string is a different instance than before, go back to that instance
	Hash::Util::hv_store(%$self, 'str', ${$origin->[0]})
		unless \$self->{str} == $origin->[0];
	# Reset the string to the original length
	substr($self->{str}, $origin->[1])= '';
	$self->{require}= $origin->[2];
	$self->{start}= $origin->[3];
}

1;
