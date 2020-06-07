package Mock::Data;
use strict;
use warnings;
use Storable 'dclone';

=head1 SYNOPSIS

  # load it up with data from plugins
  my $mockdata= Mock::Data->new(with => [ ... ]);
  
  # generate or pick data from sets
  say $mockdata->integer;    # returns a random integer
  say $mockdata->first_name; # returns a random entry from the first_name set
  
  # Can pass parameters to generators
  say $mockdata->integer(max => 50);
  
  # Can define new collections (with autoload method) on the fly
  $mockdata->merge_generators(
	stuff => [ 'things', 'junk', 'clutter' ],
  );
  say $mockdata->stuff; # returns random element of stuff collection
  
  # Template notation makes it easy to combine patterns/collections
  say $mockdata->merge_generators(
    business_suffix => [ 'Inc.', 'llc.', 'gmbh.' ],
    business_name => [
      '{surname} {industry} {business_suffix}',
      '{surname} and {surname} {business_suffix}',
    ]
  );

=head1 DESCRIPTION

This module is a generator of mock data.  It takes good ideas seen in L<Data::Faker>,
L<Mock::Populate>, and other similar modules, and combines them into a cohesive
extensible design.

Each mock data generator is called as a method on an instance of C<Mock::Data>.  This allows
generators to store persistent state between calls.  It also allows them to be configured
with per-instance settings.

=head1 ATTRIBUTES

This module defines a minimal number of attributes, to leave most of the method namespace
available for the generators themselves.  All subclasses and custom generators should attempt
to use the existing attributes instead of defining new ones.

=head2 generators

  my $generator_hashref= $mock->generators;
  $mock->generators( $new_hashref );  # clears cache

This is a hashref of named things which can generate mock data.  The things can be coderefs,
arrayrefs (select random element of the array) or instance of Mock::Data::Generator.
The data specified here may be cached in various ways after a generator has been called, so
any time you modify it you should use the methods L</set_generators> or L</merge_generators>.
However, you may modify it directly and then write the new (or same) hashref to this attribute
as an argument, which will clear the cache.

=head2 generator_state

  sub my_generator {
    $_[0]->generator_state->{__PACKAGE__.'.foo'}= $my_state;
  }

This is a hashref where generators can store temporary data.  If the instance of L<Mock::Data>
is cloned, this hashref will be deep-cloned.  Other hashref fields of the L<Mock::Data> object
are not deep-cloned, aside from the C<generators> field which is cloned one level deep.

Keys in this hash should be prefixed with either the name of the generator or name of the
package the generator was implemented from.

=cut

sub generators {
	return $_[0]{generators} if @_ == 1;
	# if being assigned, clear cache first
	%{$_[0]{_generator_cache}}= ();
	return $_[0]{generators}= $_[1];
}

sub generator_state {
	return $_[0]{generator_state} if @_ == 1;
	return $_[0]{generator_state}= $_[1];
}

=head1 METHODS

Note: All generators may be called as methods, thanks to C<AUTOLOAD>.

=head2 new

  $mock= Mock::Data->new(\@package_list);
  $mock= Mock::Data->new({
    generators => \%generator_set,
    with => \@package_list,
    
  });

Construct a new instance of Mock::Data.  If called as a method of an object, this will clone
the existing instance, applying generators on top of the set already present.

Arguments:

=over

=item C<< with => \@package_list >>

This lets you specify a list of packages whose generators should be pulled into the new object.
The plugins may also change the class of the object returned.

=item C<< generators => \%set >>

This specifies a set of generators that should be the initial value of the L</generators>
attribute.  If this is specified to L</new> called on an instance, the generators will be
merged with the ones for the instance as per L</add_generators>.

=back

=cut

sub new {
	my $self= shift;
	my %args
		= (@_ == 1 && ref $_[0] eq 'ARRAY')? ( with => $_[0] )
		: (@_ == 1 && ref $_[0] eq 'HASH')? ( %{ $_[0] } )
		: @_;
	$self= ref $self? $self->_clone
		: bless {
			generators => {},
			generator_state => {},
			_generator_cache => {},
		}, $self;
	for ($args{with}? @{ $args{with} } : ()) {
		$self->_load_plugin($_);
	}
	$self->add_generators($args{generators})
		if $args{generators};
	return $self;
}

sub _clone {
	my $self= shift;
	my $new= { %$self };
	$new->{generators}= { %{ $self->{generators} } };
	$new->{generator_state}= dclone($self->generator_state);
	$new->{_generator_cache}= {};
	$new;
}

=head2 add_generators

  $mock->add_generators( $name => $spec, ... )

Set one or more named generators.  Arguments can be given as a hashref or a list of key/value
pairs.  C<$spec> can be a coderef, an arrayref (of options) or an instance of
L<Mock::Data::Generator>.  If a previous generator existed by the same name, it will be
replaced.

Returns C<$mock>, for chaining.

Use this method instead of directly modifying the C<generators> hashref so that this module
can perform proper cache management.

=head2 merge_generators

  $mock->merge_generators( $name => $spec, ... )

Same as L</set_generators>, but if a generator of that name already exists, replace it with a
generator that returns both possible sets of results.  If the old generator was a coderef, it
will be replaced with a new generator that calls the old coderef 50% of the time.  If the old
generator and new generator are both arrayrefs, the merged generator will be a concatenation
of the arrays.

Returns C<$mock>, for chaining.

Use this method instead of directly modifying the C<generators> hashref so that this module
can perform proper cache management.

=cut

sub add_generators {
	my $self= shift;
	while (@_) {
		my ($name, $spec)= splice @_, 0, 2;
		$self->generators->{$name}= $spec;
		delete $self->{_generator_cache}{$name};
	}
}

sub merge_generators {
	my $self= shift;
	while (@_) {
		my ($name, $spec)= splice @_, 0, 2;
		my $cur= $self->generators->{$name};
		$spec= $self->_merge_generator_spec($cur, $spec) if defined $cur;
		$self->generators->{$name}= $spec;
		delete $self->{_generator_cache}{$name};
	}
}

sub _merge_generator_spec {
	my ($self, $old, $new)= @_;
	if (ref $old && ref($old)->can('merge_generator_spec')) {
		return $old->clone->merge_generator_spec($new);
	} elsif (ref $new && ref($new)->can('merge_generator_spec')) {
		return $new->clone->merge_generator_spec($old);
	} else {
		return [
			ref $old eq 'ARRAY'? @$old : ( $old ),
			ref $new eq 'ARRAY'? @$new : ( $new ),
		];
	}
}

1;
