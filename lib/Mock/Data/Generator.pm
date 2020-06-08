package Mock::Data::Generator;
use strict;
use warnings;
use Scalar::Util ();
use Carp ();

=head1 DESCRIPTION

This package provides a set of utility methods for writing generators, and an optional
abstract base class.  (a Generator does not need to inherit from this class)

=head1 GENERATORS

The most basic C<Mock::Data> generator is a simple coderef of the form

  sub ( $mockdata, \%arguments, @arguments ) { ... }

which returns a literal data item, usually a scalar.  A generator can also be any object
which has a L</evaluate> method.  The object form also allows other methods that can control
how the object is combined with others when a user wants to merge two generators into one.

=head1 METHODS

=head2 evaluate

  my $data= $generator->evaluate($mockdata, \%arguments, @arguments);

Like the coderef, this takes an instance of L<Mock::Data> as the first argument, followed by
a hashref of named arguments, followed by arbitrary positional arguments after that.

=head2 compile

  my $coderef= $generator->compile;

Return a plain coderef that invokes this generator.  The default in this abstract base class
is to return:

  sub { $self->evaluate(@_) }

=cut

sub evaluate { Carp::croak "Unimplemented" }

sub compile {
	my $self= shift;
	sub { $self->evaluate(@_) }
}

=head2 combine_generator

  my $new_generator= $self->combine_generator( $peer );

The default way to combine two generators is to create a new generator that selects each
child generator 50% of the time.  For generators that define a collection of possible data,
it may mae sense to merge the collections in a manner different than a plain 50% split.
This method allows for that custom behavior.

=cut

sub combine_generator {
	return Mock::Data::Generator::Util::uniform_set(@_);
}

=head1 EXPORTS

The following optional exported functions are available:

=cut

sub import { Mock::Data::Generator::Util->export_to_level(1, @_); }

BEGIN {
	require Exporter;
	@Mock::Data::Generator::Util::ISA= ( 'Exporter' );
	@Mock::Data::Generator::Util::EXPORT_OK=
		qw( uniform_set weighted_set inflate_template );
}

=head2 uniform_set

  $generator= uniform_set( @items )
  $generator= uniform_set( \@items )

Shortcut for L<Mock::Data::Generator::Set/new_uniform>.
Automatically calls L</inflate_template> when scalar items contain
C<< "{...}" >>, and recursively wraps arrayrefs.

=head2 weighted_set

  $generator= weighted_set( $weight => $item, ... )

Shortcut for L<Mock::RelationalData::SetPicker/new_weighted>.
Automatically calls L</inflate_template> when scalar items contain
C<< "{...}" >>, and recursively wraps arrayrefs.

=cut

sub Mock::Data::Generator::Util::uniform_set {
	return Mock::Data::Generator::Set->new_uniform(@_);
}

sub Mock::Data::Generator::Util::weighted_set {
	return Mock::Data::Generator::Set->new_weighted(@_);
}

=head2 inflate_template

  my $str_or_generator= inflate_template( $string );

This function takes a string and checks it for template substitutions.  If the string
references templates, this will return a generator object.  If the string does not, this will
return a plain string literal.

=cut

our %tpl_to_gen;
our %gen_attrs;

sub Mock::Data::Generator::Util::inflate_template {
	my ($tpl, $flags)= @_;
	# If it does not contain '{', return as-is.  Else parse (and probably cache)
	return $tpl if index($tpl, '{') == -1;
	my $cmp= _compile_template($tpl, $flags);
	if (ref $cmp eq 'CODE') {
		bless $cmp, 'Mock::Data::Generator::SubWrapper';
		$gen_attrs{Scalar::Util::refaddr $cmp}= { template => $tpl };
	}
	return $cmp;
}

@Mock::Data::Generator::SubWrapper::ISA= ( 'Mock::Data::Generator' );

sub Mock::Data::Generator::SubWrapper::template {
	return $gen_attrs{Scalar::Util::Refaddr $_[0]}{template}
}

sub Mock::Data::Generator::SubWrapper::compile {
	return $_[0];
}

sub Mock::Data::Generator::SubWrapper::evaluate {
	shift->(@_);
}

sub Mock::Data::Generator::SubWrapper::DESTROY {
	delete $gen_attrs{Scalar::Util::refaddr $_[0]};
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
		elsif ($parts[$i] =~ /^\{ % ([0-9A-Z]+) \} $/x) {
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
		)*
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
		my $generator= $_[0]->generators->{$gen_name}
			|| Carp::croak "No such generator $gen_name";
		# The @args we parsed get added to the \%args passed to the function on each call
		$generator->($_[0], !@named_args? $_[1] : { %{$_[1]}, @named_args }, @list_args);
	};
}

1;
