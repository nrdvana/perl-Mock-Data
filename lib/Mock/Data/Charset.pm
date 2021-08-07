package Mock::Data::Charset;
use strict;
use warnings;
use List::Util 'shuffle';

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


sub parse_regex {
	my $re= shift;
	return _parse_regex({}) for "$re";
}

our %_regex_syntax_unsupported= (
	'' => { map { $_ => 1 } qw( $ ) },
	'\\' => { map { $_ => 1 } qw( B b A Z z G g K k ) },
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
		elsif (/\G ( \[ | \\w | \\W | \\s | \\S | \\d | \\D | \\N | \\Z | \. | \^ | \$ ) /gcx) {
			if (ord $1 == ord '[') {
				push @$expr, _parse_charset();
			}
			elsif (ord $1 == ord '\\') {
				if ($1 eq "\\Z") {
					push @$expr, { at => { end => 1 } }
				}
				else {
					my $callback= $_parse_charset_backslash{substr($1,1)};
					my $charset= { classes => [] };
					$callback->($charset);
					push @$expr, $charset;
				}
			}
			elsif (ord $1 == ord '.') {
				push @$expr, { classes => [ $flags->{s}? 'Any' : '\\N' ] };
			}
			elsif (ord $1 == ord '$') {
				push @$expr, { at => { end => ($flags->{m}? 'LF' : 'FinalLF') } };
			}
			elsif (ord $1 == ord '^') {
				push @$expr, { at => { start => ($flags->{m}? 'LF' : 1 ) } };
			}
		}
		# repetition?
		elsif (/\G ( \? | \* | \+ | \{ ([0-9]*) (,)? ([0-9]*) \} ) /gcx) {
			my @rep;
			if (ord $1 == ord '?') {
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
				next if defined $expr->[-1]{repeat};
			}
			$expr->[-1]{repeat}= \@rep;
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

sub generate_string_for_regex {
	my $regex= shift;
	my $parse= parse_regex($regex);
	my $buf= '';
	my %flags;
	_generate_string_for_regex_node($parse, \$buf, \%flags)
		or die "Regex assertions could not be met (such as '^' or '\$').  Final attempt was: \"".$buf."\"";
	return $buf;
	## 75% chance to prefix garbage to the string, unless the pattern is anchored
	#if (!$flags->{start} && int rand 4) {
	#	my $prefix= map chr(32 + int rand 96), 1 .. (1+int(rand 8));
	#	# if /m is in effect, 50% chance that we prefix some random garbage ending with "\n"
	#	$prefix .= "\n" if $flags->{'^'} && $flags->{m};
	#	$str= $prefix . $str;
	#}
	## if anchored with \Z, append nothing
	#if ((!$flag->{end} || $flags->{end} eq 'LF'
	## If anchored with '$', and not flag /m, sometimes append a newline
	#
	## 75% chance to suffix garbage to the string, unless the pattern is anchored
	#if (!($flag->{'$'} && !$flags->{m} 
	#	if ($flags->{m} && int rand 4) {
	#		$str= (map chr(1 + int rand 126), 1 .. int(rand 8)) . $str;
	#	}
	#}
	#if ($flags->{'$'}) {
	#	if ($flags->{m} && int rand(2)) {
	#	}
	#}
}

sub build_generator_for_regex {
	my $regex= shift;
	my $parse= parse_regex($regex);
	return sub {
		my $buf= '';
		my %flags;
		_generate_string_for_regex_node($parse, \$buf, \%flags)
			or die "Regex assertions could not be met (such as '^' or '\$').  Final attempt was: \"".$buf."\"";
		return $buf;
	}
}

sub _generate_string_for_regex_node {
	my $parse= shift;
	#use DDP;
	#print STDERR "# Node ".&np($parse)."\n";
	my ($buf_ref, $flags)= @_;
	# Handle repetitions
	my $rep= $parse->{repeat};
	my $n= !defined $rep? 1
		: !defined $rep->[1]? $rep->[0] + rand(8)
		: $rep->[0] + rand($rep->[1] - $rep->[0] + 1);
	#print STDERR "#   n=$n\n";
	# zero repetitions is automatic success
	return 1 unless $n;
	rep: for my $i (1 .. $n) {
		# If the current node has alternate options, try them in random order until one works
		if ($parse->{or}) {
			my $orig_len= length $$buf_ref;
			my %orig_flags= %$flags;
			# Pick one at random.  It will almost always work on the first try, unless the user
			# has anchor constraints in the pattern.
			my $opt= $parse->{or}[ rand scalar @{$parse->{or}} ];
			next rep if _generate_string_for_regex_node($opt, @_);
			# if it fails, try all the others in random order
			for (shuffle grep { $_ != $opt } @{$parse->{or}}) {
				# reset output
				substr($$buf_ref, $orig_len)= '';
				%$flags= %orig_flags;
				# append something new
				next rep if _generate_string_for_regex_node($_, @_);
			}
			# failure...
			return 0;
		}
		# If the node is an expression, build a string from each part and concatenate them
		elsif ($parse->{expr}) {
			for (@{$parse->{expr}}) {
				# If it's a literal string, append that.
				if (!ref $_) {
					# can't append if string is finalized
					return 0 if $flags->{end} && $flags->{end} eq '1';
					$$buf_ref .= $_;
					delete $flags->{end}; # end flag no longer applies
					delete $flags->{can_add_LF};
				}
				# Else process the node
				else {
					_generate_string_for_regex_node($_, @_)
						or return 0;
				}
			}
		}
		# If the node has an 'at' requirement, see if we can match it.
		# If not, give up on this attempt.
		elsif ($parse->{at}) {
			my ($start, $end)= @{$parse->{at}}{'start','end'};
			if ($start) {
				# If regex used /m the '^' may refer to start of string or a line.
				# If any output has been added, then this is the only way {at}{start} can succeed.
				if (!length $$buf_ref) {
					# successful match at start of string.
					# This '^' marker adds the requirement for the whole output.
					$flags->{start}= $start;
					next rep;
				}
				if ($start eq 'LF') {
					# does output already end with "\n"?  then it's a match.
					next rep if $$buf_ref =~ /\n\Z/;
					# Can we append "\n" according to the previous node?
					# TODO: determmine whether chars can be appended, or if final char may become LF
					if ($flags->{can_add_LF}) {
						$$buf_ref .= "\n";
						next rep;
					}
				}
				# failure
				return 0;
			}
			if ($end) {
				# IF $end is '1', it means only the absolute end of the string can match.
				# Any other variant may consume (and therefore generate) a linefeed.
				# Maybe append an additional linefeed if one is already present.
				if ($end ne '1') {
					if (int rand 2) {
						$$buf_ref .= "\n";
						$end= 1 if $end eq 'FinalLF'; # FinalLF now needs to be actual end
					}
					else {
						$flags->{can_add_LF}++;
					}
				}
				$flags->{end}= $end;
			}
		}
		else {
			# It is a character set.  Build the inversion list if not built yet.
			$parse->{invlist}   ||= _parsed_charset_to_invlist($parse, $parse->{flags}{a}? 127 : 0x10FFFF);
			$parse->{inv_index} ||= create_invlist_index($parse->{invlist});
			#print STDERR "# select from ".join(", ", $parse->{invlist})."\n";
			# can't append if string is finalized
			return 0 if $flags->{end} && $flags->{end} eq '1';
			# Select a random character
			$$buf_ref .= chr get_invlist_element(int rand($parse->{inv_index}[-1]), $parse->{invlist}, $parse->{inv_index});
			delete $flags->{can_add_LF};
			delete $flags->{end};
		}
	}
	return 1;
}

1;
