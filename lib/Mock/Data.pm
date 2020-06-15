package Mock::Data;
use strict;
use warnings;
use Storable ();
use Module::Runtime ();
BEGIN {
	if ("$]" >= 5.010_000) {
		require mro;
	} else {
		require MRO::Compat;
	}
	mro::set_mro __PACKAGE__, 'c3';
}
use Mock::Data::Generator;

=head1 SYNOPSIS

  # load it up with data from plugins
  my $mockdata= Mock::Data->new([qw/ Num Text Contact /);
  
  # generate or pick data from sets
  say $mockdata->integer;    # returns a random integer
  say $mockdata->first_name; # returns a random entry from the first_name set
  
  # Can pass parameters to generators
  say $mockdata->integer({ max => 50 });
  
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
		$self= $self->_load_plugin($_);
	}
	$self->add_generators($args{generators})
		if $args{generators};
	return $self;
}

sub _load_plugin {
	my ($self, $name)= @_;
	my @fail;
	for ("Mock::Data::$name", $name) {
		unless ($_->can('apply_mockdata_plugin')) {
			unless (eval { Module::Runtime::require_module($_) }) {
				push @fail, "Can't load $_";
				next;
			}
			unless ($_->can('apply_mockdata_plugin')) {
				push @fail, "No method $_->apply_plugin";
				next;
			}
		}
		my $new= $_->apply_mockdata_plugin($self);
		ref($new) && ref($new)->can('call_generator')
			or Carp::croak("$_->apply_mockdata_plugin did not return a Mock::Data");
		return $new;
	}
	Carp::croak("Can't load plugin $name: ".join('; ', @fail));
}

sub _clone {
	my $self= shift;
	my $new= { %$self };
	$new->{generators}= { %{ $self->{generators} } };
	$new->{generator_state}= Storable::dclone($self->generator_state);
	$new->{_generator_cache}= {};
	$new;
}

=head2 add_generators

  $mockdata->add_generators( $name => $spec, ... )

Set one or more named generators.  Arguments can be given as a hashref or a list of key/value
pairs.  C<$spec> can be a coderef, an arrayref (of options) or an instance of
L<Mock::Data::Generator>.  If a previous generator existed by the same name, it will be
replaced.

If the C<$name> of the generator is a package-qualified name, the generator is added under
both the long and short name.  For example, C<< merge_generators( 'MyPlugin::gen' => \&gen ) >>
will register \&gen as both C<'MyPlugin::gen'> and an alias of C<'gen'>.  However, C<'gen'>
will only be added if it didn't already exist.  This allows plugins to refer to eachother's
names without collisions.

Returns C<$mockdata>, for chaining.

Use this method instead of directly modifying the C<generators> hashref so that this module
can perform proper cache management.

=head2 merge_generators

  $mock->merge_generators( $name => $spec, ... )

Same as L</add_generators>, but if a generator of that name already exists, replace it with a
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
	my @args= @_ == 1? %{ $_[0] } : @_;
	while (@args) {
		my ($name, $spec)= splice @args, 0, 2;
		$self->generators->{$name}= $spec;
		delete $self->{_generator_cache}{$name};
		if ($name =~ /::([^:]+)$/ and !defined $self->generators->{$1}) {
			$self->generators->{$1}= $spec;
		}
	}
	$self;
}

sub merge_generators {
	my $self= shift;
	my @args= @_ == 1? %{ $_[0] } : @_;
	while (@args) {
		my ($name, $spec)= splice @args, 0, 2;
		my $merged= $spec;
		if (defined (my $cur= $self->generators->{$name})) {
			$merged= $self->_merge_generator_spec($cur, $spec);
			delete $self->{_generator_cache}{$name};
		}
		$self->generators->{$name}= $merged;
		if ($name =~ /::([^:]+)$/) {
			($name, $merged)= ($1, $spec);
			if (defined (my $cur= $self->generators->{$name})) {
				$merged= $self->_merge_generator_spec($cur, $spec);
				delete $self->{_generator_cache}{$name};
			}
			$self->generators->{$name}= $merged;
		}
	}
	$self;
}

sub call_generator {
	my $self= shift;
	my $name= shift;
	my $gen= $self->{_generator_cache}{$name} ||= do {
		my $spec= $self->{generators}{$name};
		defined $spec or Carp::croak("No such generator '$name'");
		Mock::Data::Generator::Util::new_generator($spec)->compile;
	};
	$gen->($self, @_);
}

our $AUTOLOAD;
sub AUTOLOAD {
	my $self= shift;
	Carp::croak "No method $AUTOLOAD in package $self" unless ref $self;
	my $name= substr($AUTOLOAD, rindex($AUTOLOAD,':')+1);
	$self->call_generator($name, @_);
	# don't install, because generators are defined per-instance not per-package
}

sub DESTROY {} # prevent AUTOLOAD from triggering on ->DESTROY

=head1 EXTENSION UTILITIES

When writing plugins for Mock::Data, the following functions / methods may be useful:

=head2 _add_method_table

  my $subclass= $class->_add_method_table($package_name);
  my $reblessed= $object->_add_method_table($package_name);

This method can be called on a class or instance to add a new package to the ISA list.
It does this by creating a derived class from whatever the current class is.  If called
on an instance, it also re-blesses the instance to the new class.  If the class or
instance already "isa $package_name", nothing changes.

This does *not* check if $package_name is loaded.  That is the caller's responsibility.

=cut

our %auto_subclasses;

sub _add_method_table {
	my ($self, $new_parent)= @_;
	my $class= ref $self || $self;
	# Nothing to do if already part of this class/object
	return $self if $class->isa($new_parent);
	# Determine what the new @ISA will be
	my @new_isa= defined $auto_subclasses{$class}
		? @{$auto_subclasses{$class}}
		: ($class);
	# Remove base classes of new-parent from ISA list.
	@new_isa= grep !$new_parent->isa($_), @new_isa;
	# If no classes remain (new_parent has its own inheritence hierarchy that includes
	# everything needed) then $new_class is just $new_parent
	my $new_class;
	if (!@new_isa) {
		$new_class= $new_parent;
	} else {
		push @new_isa, $new_parent;
		# Now find if this combination was already composed, else create it.
		$new_class= _name_for_combined_isa(@new_isa);
		if (!$auto_subclasses{$new_class}) {
			no strict 'refs';
			@{"${new_class}::ISA"}= @new_isa;
			$auto_subclasses{$new_class}= \@new_isa;
		}
	}
	return ref $self? bless($self, $new_class) : $new_class;
}

# When choosing a name for a new @ISA list, the name could be something as simple as ::AUTO$n
# with an incrementing number, but that wouldn't be helpful in a stack dump.  But, a package
# name fully containing the ISA package names could get really long and also be unhelpful.
# Compromise by shortening the names by removing Mock::Data prefix and removing '::'.
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
	while (defined $auto_subclasses{$class . $suffix}
		&& $isa_key ne join "\0", grep { $_ ne 'Mock::Data' } @{$auto_subclasses{$class . $suffix}}
	) {
		$suffix= '_' . ++$iter;
	}
	$class . $suffix;
}

sub _merge_generator_spec {
	my ($self, $old, $new)= @_;
	if (ref $old && ref($old)->can('combine_generator')) {
		return $old->combine_generator($new);
	} elsif (ref $new && ref($new)->can('combine_generator')) {
		return $new->combine_generator($old);
	} else {
		return [
			(ref $old eq 'ARRAY'? @$old : ( $old )),
			(ref $new eq 'ARRAY'? @$new : ( $new )),
		];
	}
}

1;
