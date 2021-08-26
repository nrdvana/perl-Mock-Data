package Mock::Data::Generator;
use strict;
use warnings;
use Scalar::Util ();
use Carp ();

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

  my $data= $generator->generate($mockdata, \%arguments, @arguments);

Like the coderef, this takes an instance of L<Mock::Data> as the first non-self argument,
followed by a hashref of named arguments, followed by arbitrary positional arguments after
that.

=head2 compile

  my $coderef= $generator->compile;

Return a plain coderef that invokes this generator.  The default in this abstract base class
is to return:

  sub { $self->generate(@_) }

=cut

sub generate { Carp::croak "Unimplemented" }

sub compile {
	my $self= shift;
	sub { $self->generate(@_) }
}

=head2 combine_generator

  my $new_generator= $self->combine_generator( $peer );

The default way to combine two generators is to create a new generator that selects each
child generator 50% of the time.  For generators that define a collection of possible data,
it may be preferred to merge the collections in a manner different than a plain 50% split.
This method allows for that custom behavior.

=cut

sub combine_generator {
	return Mock::Data::Util::uniform_set(@_);
}

require Mock::Data::Set;
1;
