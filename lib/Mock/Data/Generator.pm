package Mock::Data::Generator;
use strict;
use warnings;
require Scalar::Util;
require Carp;

# ABSTRACT: Utilities and optional base class for authoring generators
# VERSION

=head1 DESCRIPTION

This package provides a set of utility methods for writing generators, and an optional
abstract base class.  (a Generator does not need to inherit from this class)

=head1 GENERATORS

The most basic C<Mock::Data> generator is a simple coderef of the form

  sub ( $mockdata, \%arguments, @arguments ) { ... }

which returns a literal data item, usually a scalar.  A generator can also be any object
which has a L</generate> method.  Using an object provides more flexibility to handle
cases where a user wants to combine generators.

=head1 METHODS

=head2 generate

  my $data= $generator->generate($mockdata, \%named_params, @pos_params);

Like the coderef, this takes an instance of L<Mock::Data> as the first non-self argument,
followed by a hashref of named parameters, followed by arbitrary positional parameters after
that.

=head2 compile

  my $callable= $generator->compile(@defaults);

Return a generator that is optimized for calling like a coderef, with the given C<@defaults>.
This implementation just wraps C<< $self->generate(@defaults) >> in a coderef and blesses it
as L<Mock::Data::GeneratorSub>.  If appropriate, the coderef should allow further parameters
to override the defaults.

=cut

sub generate { Carp::croak "Unimplemented" }

sub compile {
	my $self= shift;
	# If no arguments, add a simple wrapper around ->generate
	return bless sub { $self->generate(@_) }, 'Mock::Data::GeneratorSub' unless @_ > 1;
	# Else wrap arguments in a new coderef
	my @default= @_;
	my $default_opts_hash= @default && ref $default[0] eq 'HASH'? $default[0] : undef;
	my $code= $self->can('generate');
	return bless sub {
		my $mock= shift;
		return $code->($self, $mock, @default) unless @_;
		# Merge any options-by-name newly supplied with options-by-name from @default
		unshift @_, (ref $_[0] eq 'HASH')? { %{$default_opts_hash}, %{shift @_} } : $default_opts_hash
			if $default_opts_hash;
		return $code->($self, $mock, @_);
	}, 'Mock::Data::GeneratorSub';
}

=head2 combine_generator

  my $new_generator= $self->combine_generator( $peer );

The default way to combine two generators is to create a new generator that selects each
child generator 50% of the time.  For generators that define a collection of possible data,
it may be preferred to merge the collections in a manner different than a plain 50% split.
This method allows for that custom behavior.

=cut

sub combine_generator {
	return Mock::Data::Set->new_uniform(@_);
}

=head2 clone

A generator that wants to perform special behavior when the C<Mock::Data> instance gets cloned
can implement this method.  I can't think of any reason a generator should ever need this,
since the L<Mock::Data/generator_state> gets cloned.  Lack of the method indicates the
generator doesn't need this feature.

=cut

require Mock::Data::Set;
1;
