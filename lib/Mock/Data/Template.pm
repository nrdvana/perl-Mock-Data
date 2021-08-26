package Mock::Data::Template;
use strict;
use warnings;
use overload '""' => sub { shift->to_string };
require Mock::Data::Generator;
our @ISA= ( 'Mock::Data::Generator' );
require Carp;

# ABSTRACT: Create a generator that plugs other templates into a string
# VERSION

=head1 SYNOPSIS

  my $mock= Mock::Data->new(
    generators => {
      first_name => ['Alex','Pat'],
      last_name => ['Smith','Jones'],
      name => Mock::Data::Template->new("{first_name} {last_name}"),
      ten_words => "{join word count=10}",
    }
  );

=head1 DESCRIPTION

L<Mock::Data> provides a convenient and simple templating system where C<< "{...}" >> in the
text gets replaced by the output of another generator.  The contents of the curly braces can
be a simple template name (which is found by name in the collection of generators of the current
C<Mock::Data> ) or it can include parameters, both positional and named.

=head2 SYNTAX

  # Call without parameters
  "literal text {template_name} literal text"
  
  # Call with positional parameters
  "literal text {template_name literal_param_1 literal_param_2} literal text"
  
  # Call with named parameters
  "literal text {template_name param5=literal_val} literal text"
  
  # Call with whitespace in parameter (hex escapes)
  "literal text {template_name two{#20}words} literal text"
  
  # Call with zero-length string parameter (prefix => "")
  "literal text {template_name prefix={}}"
  
  # Call with nested templates
  "{template1 text{#20}with{#20}{template2}{#20}embedded}"

=head1 CONSTRUCTOR

=head2 new

  Mock::Data::Template->new($template);
				   ...->new(template => $template);

This constructor only accepts one attribute, C<template>, which will be immediately parsed to
check for syntax errors.  Note that references to other generators are not resolved until the
template is executed, which may cause exceptions if generators of those names are not present
in the C<Mock::Data> instance.

Instances of C<Mock::Data::Template> do not hold references to the C<Mock::Data> or anything in
it, and may be shared freely.

=cut

sub new {
	my $class= shift;
	my %self= (@_ == 1 && !ref $_[0])? ( template => $_[0] )
		: (@_ == 1 && ref $_[0] eq 'HASH')? %{$_[0]}
		: @_ > 1? @_
		: Carp::croak("Invalid constructor arguments to $class");
	# Parse now, to report errors
	$self{_compiled}= _compile_template($self{template});
	bless \%self, $class;
}

=head1 ATTRIBUTES

=head2 template

The template string passed to the constructor

=cut

sub template { shift->{template} }

=head1 METHODS

=head2 compile

Return a coderef that executes the generator.

=head2 generate

Evaluate the template on the current L<Mock::Data> and return the string.

=cut

sub compile {
	my $cmp= $_[0]{_compiled};
	return ref $cmp? $cmp : sub { $cmp };
}

sub generate {
	my $cmp= shift->{_compiled};
	return ref $cmp? $cmp->(@_) : $cmp;
}

=head2 to_string

Templates stringify as C<< "template('original_text')" >>

=cut

sub to_string {
	"template('" . shift->template . "')";
}

sub _compile_template {
	my ($tpl, $flags)= @_;
	# Split the template on each occurrence of "{...}" but respect nested {}
	my @parts= split /(
		\{                 # curly braces
			(?:
				(?> [^{}]+ )    # span of non-brace (no backtracking)
				|
				(?1)            # or recursive match of whole pattern
			)*
		\}
		)/x, $tpl;
	# Convert the odd-indexed elements (contents of {...}) into calls to generators
	for (my $i= 1; $i < @parts; $i += 2) {
		if ($parts[$i] eq '{}') {
			$parts[$i]= '';
		}
		elsif ($parts[$i] =~ /^\{ [#] ([0-9A-Z]+) \} $/x) {
			$parts[$i]= chr hex $1;
		}
		elsif ($parts[$i] =~ /^\{\w/) {
			$parts[$i]= _compile_template_call(substr($parts[$i], 1, -1), $flags);
		}
		else {
			Carp::croak "Invalid template notation '$parts[$i]'";
		}
	}
	# Combine adjacent scalars in the list
	@parts= grep ref || length, @parts;
	for (my $i= $#parts - 1; $i >= 0; --$i) {
		if (!ref $parts[$i] and !ref $parts[$i+1]) {
			$parts[$i] .= splice(@parts, $i+1, 1);
		}
	}
	return
		# No parts? empty string.
		!@parts? ''
		# One part of plain scalar? return it.
		: @parts == 1 && !ref $parts[0]? $parts[0]
		# Error context requested?
		: ($flags && $flags->{add_err_context})? sub {
			my $ret;
			local $@;
			eval {
				$ret= join '', map +(ref $_? $_->(@_) : $_), @parts;
				1;
			} or do {
				$@ =~ s/$/ for template '$tpl'/m;
				Carp::croak "$@";
			};
			$ret;
		}
		# One part which is already a generator?
		: @parts == 1? $parts[0]
		# Multiple parts get concatenated, while calling nested generators
		: sub { join '', map +(ref $_? $_->(@_) : $_), @parts };
}

sub _compile_template_call {
	my ($name_and_args, $flags)= @_;
	my @args;
	while ($name_and_args =~ /\G(
		(?:
			(?> [^{ ]+ )         # span of non-space non-lbrace (no backtrack)
			|
			(\{                  # or matched braces containing...
				(?:
					(?> [^{}]+ )    # span of non-brace (no backtrack)
					|
					(?2)            # or recursive match of matched braces
				)*
			\})
		)+
		) [ ]*                   # don't capture trailing space
		/xgc
	) {
		push @args, $1
	}
	my $gen_name= shift @args;
	my (@calls, @named_args, @list_args);
	# Each argument could be a literal value, or a name=value pair, and the values could include templates
	for (@args) {
		# Argument is NAME=VALUE
		if ($_ =~ /^([^{=]+)=(.*)/) {
			push @named_args, $1, $2;
			# Check if VALUE contains template substitutions
			if (index($2, '{') >= 0) {
				my $gen= _compile_template($2);
				if (!ref $gen) {
					$named_args[-1]= $gen;
				} else {
					my $i= $#named_args;
					push @calls, sub { $named_args[$i]= $gen->(@_) };
				}
			}
		} else {
			push @list_args, $_;
			# Check of VALUE contains template substitutions
			if (index($_, '{') >= 0) {
				my $gen= _compile_template($_);
				if (!ref $gen) {
					$list_args[-1]= $gen;
				} else {
					my $i= $#list_args;
					push @calls, sub { $list_args[$i]= $gen->(@_) };
				}
			}
		}
	}
	return sub {
		# Run any nested templates that were part of the arguments to this template
		# In most cases this will be an empty list.
		$_->(@_) for @calls;
		# $_[0] is $mockdata.   $_[1] is \%named_args from caller of generator.
		$_[0]->call_generator(
			$gen_name,
			# The @args we parsed get added to the \%args passed to the function on each call
			!@named_args? $_[1] : { %{$_[1]}, @named_args },
			@list_args
		);
	};
}

1;
