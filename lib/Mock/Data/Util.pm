package Mock::Data::Util;
use strict;
use warnings;
require Exporter;
require Carp;
our @ISA= ( 'Exporter' );
our @EXPORT_OK= qw( uniform_set weighted_set inflate_template coerce_generator mock_data_subclass
	charset
);

# ABSTRACT: Exportable functions to assist with declaring mock data
# VERSION

=head1 SYNOPSIS

  use Mock::Data qw/
    uniform_set
    weighted_set
    inflate_template
    coerce_generator
    mock_data_subclass
  /;

=head1 DESCRIPTION

This module contains utility functions for L<Mock::Data>.  These functions can be imported
from this utility module, or (more conveniently) from L<Mock::Data> itself.

=head1 EXPORTS

Nothing is exported by default.  The following functions are available:

=head2 uniform_set

  $generator= uniform_set( @items )
  $generator= uniform_set( \@items )

Shortcut for L<Mock::Data::Set/new_uniform>.
Automatically calls L</inflate_template> when scalar items contain
C<< "{...}" >>, and recursively wraps arrayrefs.

=head2 weighted_set

  $generator= weighted_set( $item => $weight, ... )

Shortcut for L<Mock::RelationalData::SetPicker/new_weighted>.
Automatically calls L</inflate_template> when scalar items contain
C<< "{...}" >>, and recursively wraps arrayrefs.

=cut

sub uniform_set {
	return Mock::Data::Set->new_uniform(@_);
}

sub weighted_set {
	return Mock::Data::Set->new_weighted(@_);
}

=head2 charset

  $generator= charset('A-Z');

Shortcut for L<Mock::Data::Charset/new>, which takes a perl-regex-notation
character set string, or list of attributes.

=cut

sub charset {
	return Mock::Data::Charset->new(@_);
}

=head2 inflate_template

  my $str_or_generator= inflate_template( $string );

This function takes a string and checks it for template substitutions.  If the string
contains curly brace references, or things that might be mistaken for references, this will
return a generator object.  If the string does not, this will return a plain string literal.

=cut

sub inflate_template {
	my ($tpl, $flags)= @_;
	# If it does not contain '{', return as-is.  Else parse (and probably cache)
	return $tpl if index($tpl, '{') == -1;
	my $cmp= _compile_template($tpl, $flags);
	$cmp= Mock::Data::SubWrapper->_new($cmp, { template => $tpl })
		if ref $cmp eq 'CODE';
	return $cmp;
}

=head2 coerce_generator

  my $generator= coerce_generator($spec);

Returns a L<Mock::Data::Generator> wrapping the argument.  The following types are handled:

=over

=item Scalar without "{"

Returns a Generator that always returns the constant scalar.

=item Scalar with "{"

Returns a Generator that performs template substitution on the string.

=item ARRAY ref

Returns a L</uniform_set>.

=item HASH ref

Returns a L</weighted_set>.

=item CODE ref

Returns the coderef, blessed as a generator.

=item C<< $obj->can('compile' >>

Any object which has a C<compile> method is returned as-is.

=back

=cut

sub coerce_generator {
	my ($spec, $flags)= @_;
	if (!ref $spec) {
		my $gen= index($spec, '{') == -1? $spec : _compile_template($spec, $flags);
		if (!ref $gen) {
			return $gen if $flags && $flags->{or_scalar};
			my $const= $gen;
			$gen= sub () { $const };
		}
		$gen= Mock::Data::SubWrapper->_new($gen, { template => $spec });
		return $gen;
	}
	elsif (ref $spec eq 'ARRAY') {
		return Mock::Data::Set->new(items => $spec);
	}
	elsif (ref $spec eq 'HASH') {
		return Mock::Data::Set->new_weighted(%$spec);
	}
	elsif (ref $spec eq 'CODE') {
		return Mock::Data::SubWrapper->_new($spec);
	}
	elsif (ref($spec)->can('compile')) {
		return $spec;
	}
	else {
		Carp::croak("Don't know how to make '$spec' into a generator");
	}
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

=head2 mock_data_subclass

  my $subclass= mock_data_subclass($class, @package_names);
  my $reblessed= mock_data_subclass($object, @package_names);

This method can be called on a class or instance to create a new package which inherits
from the original and all packages in the list.  If called on an instance, it also
re-blesses the instance to the new class.  All redundant items are removed from the
combined list. (such as where one of the classes already inherits from one of the others).

This does *not* check if $package_name is loaded.  That is the caller's responsibility.

=cut

sub mock_data_subclass {
	my $self= shift;
	my $class= ref $self || $self;
	my @to_add= grep !$class->isa($_), @_;
	# Nothing to do if already part of this class/object
	return $self unless @to_add;
	# Determine what the new @ISA will be
	my @new_isa= defined $Mock::Data::auto_subclasses{$class}
		? @{$Mock::Data::auto_subclasses{$class}}
		: ($class);
	# Remove redundant classes
	for my $next_class (@to_add) {
		next if grep $_->isa($next_class), @new_isa;
		@new_isa= grep !$next_class->isa($_), @new_isa;
		push @new_isa, $next_class;
	}
	# If only one class remains, this this one class already defined an inheritance for all
	# the others.  Use it directly.
	my $new_class;
	if (@new_isa == 1) {
		$new_class= $new_isa[0];
	} else {
		# Now find if this combination was already composed, else create it.
		$new_class= _name_for_combined_isa(@new_isa);
		if (!$Mock::Data::auto_subclasses{$new_class}) {
			no strict 'refs';
			@{"${new_class}::ISA"}= @new_isa;
			$Mock::Data::auto_subclasses{$new_class}= \@new_isa;
		}
	}
	return ref $self? bless($self, $new_class) : $new_class;
}

# When choosing a name for a new @ISA list, the name could be something as simple as ::AUTO$n
# with an incrementing number, but that wouldn't be helpful in a stack dump.  But, a package
# name fully containing the ISA package names could get really long and also be unhelpful.
# Compromise by shortening the names by removing Mock::Data prefix and removing '::' and '_'.
# If this results in a name collision (seems unlikely), add an incrementing number on the end.
sub _name_for_combined_isa {
	my @parts= grep { $_ ne 'Mock::Data' } @_;
	my $isa_key= join "\0", @parts;
	for (@parts) {
		$_ =~ s/^Mock::Data:://;
		$_ =~ s/::|_//g;
	}
	my $class= join '_', 'Mock::Data::_AUTO', @parts;
	my $iter= 0;
	my $suffix= '';
	# While iterating, check to see if that package uses the same ISA list as this new request.
	while (defined $Mock::Data::auto_subclasses{$class . $suffix}
		&& $isa_key ne join("\0",
			grep { $_ ne 'Mock::Data' } @{$Mock::Data::auto_subclasses{$class . $suffix}}
		)
	) {
		$suffix= '_' . ++$iter;
	}
	$class . $suffix;
}

# included last, because they depend on this module.
require Mock::Data::Set;
require Mock::Data::Charset;
require Mock::Data::SubWrapper;
