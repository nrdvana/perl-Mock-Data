package Mock::Data::Set;
use strict;
use warnings;
require Mock::Data::Generator;
our @ISA= ('Mock::Data::Generator');

# ABSTRACT: Generator which returns one item from a set
# VERSION

=head1 SYNOPSIS

  use Mock::Data::Generator 'uniform_set', 'weighted_set';
  $gen= uniform_set( 'a', 'b', 'c', 'd' )->compile;
  $value= $gen->($mockdata);   # 25% chance of each of the items
  
  $gen= weighted_set( a => 1, b => 9 )->compile;
  $value= $gen->($mockdata);   # 10% chance of 'a', 90% chance of 'b'
  
  $gen= uniform_set( 'a', [ 'b', 'c' ] )->compile;
  $value= $gen->($mockdata);   # 50% chance of 'a', 25% chance of 'b', 25% chance of 'c'

=head1 DESCRIPTION

This object selects a random element from a list.  All items are equal probability
unless C<weights> are specified to change the probability.  The items of the list
may be templates (as per L<Mock::Data::Generator/compile_template>) which means
they may also be arrayrefs that turn into a nested C<Set> object.

The object overloads the method call operator, so it can act as a coderef, but you can also
call L</compile> to get a native coderef.

=head1 ATTRIBUTES

=head2 items

The arrayref of items which can be returned by this generator.  Do not modify this array.
If you need to change the list of items, assign a new array to this attribute.

=head2 weights

An optional arrayref of values, one value per element of C<items>.  The weight values
are on an arbitrary scale chosen by the user, such that the sum of them adds up to 100%.

=cut

sub items {
	return $_[0]{items} if @_ == 1;
	delete $_[0]{_compiled_items};
	delete $_[0]{_odds_table} if $#{$_[0]{items}} != $#{$_[1]};
	return $_[0]{items}= $_[1];
}

sub weights {
	return $_[0]{weights} if @_ == 1;
	delete $_[0]{_odds_table};
	return $_[0]{weights}= $_[1];
}

=head1 METHODS

=head2 new

Takes a list or hashref of attributes and returns them as an object.

=head2 new_uniform

  $picker= $class->new_uniform(@items);

Construct a C<SetPicker> from a list of items, where each item may be a template or
other valid specification for C<compile_generator>.  Each item is given a uniform
probability.

=head2 new_weighted

  $picker= $class->new_weighted($item => $weight, ...);

Construct a C<SetPicker> from a list of pairs of weight and item.  Item may be a template
or other valid specification for C<compile_generator>.  The 

=cut

sub new {
	my $class= shift;
	my %args= @_ == 1 && ref $_[0] eq 'HASH'? %{$_[0]} : @_;
	bless \%args, $class;
}

sub new_uniform {
	my $class= shift;
	my $items= @_ == 1 && ref $_[0] eq 'ARRAY'? shift : [@_];
	$class->new(items => $items);
}

sub new_weighted {
	my $class= shift;
	my (@items, @weights);
	while (@_) {
		push @items, shift;
		push @weights, shift;
	}
	$class->new(items => \@items, weights => \@weights);
}

=head2 generate

  $val= $picker->generate($datagen, \%args);

Return one random item from the set.  This should be called with the reference
to the L<Mock::DataGen> and optional named arguments. (as for any generator)

=cut

sub generate {
	my $self= shift;
	my $items= $self->items;
	my $pick;
	if (!$self->{weights}) {
		$pick= rand( scalar @$items );
	} else {
		# binary search for the random number
		my $tbl= $self->_odds_table;
		my ($min, $max, $r)= (0, $#$items, rand);
		while ($min+1 < $max) {
			my $mid= int(($max+$min)/2);
			if ($r < $tbl->[$mid]) { $max= $mid-1; }
			else { $min= $mid; }
		}
		$pick= ($max > $min && $tbl->[$max] <= $r)? $max : $min;
	}
	my $cmp_item= $self->{_compiled_items}[$pick] ||= _maybe_compile($items->[$pick]);
	return ref $cmp_item? $cmp_item->(@_) : $cmp_item;
}

sub _odds_table {
	$_[0]{_odds_table} ||= $_[0]->_build__odds_table;
}

sub _build__odds_table {
	my $self= shift;
	my $items= $self->items;
	my $weights= $self->weights;
	my $total= 0;
	$total += ($weights->[$_] ||= 1)
		for 0..$#$items;
	my $sum= 0;
	return [ map { my $x= $sum; $sum += $_; $x/$total } @$weights ]
}

sub _maybe_compile {
	my $spec= shift;
	!ref $spec? do {
		my $x= Mock::Data::Util::inflate_template($spec);
		!$x? sub { $x } : $x  # wrap false scalars in a coderef so they are true
	}
	: ref $spec eq 'ARRAY'? __PACKAGE__->new_uniform($spec)->compile
	: ref $spec eq 'CODE'? $spec
	: ref($spec)->can('compile')? $spec->compile
	: Carp::croak("Don't know how to compile '$spec'");
}

=head2 combine_generator

  my $merged= $self->combine_generator($peer);

If the C<$peer> is an instance of C<Mock::Data::Set>, this will take the items and weights
of the peer, combine with the items and weights of the current object, and create a new set.

=cut

sub combine_generator {
	my ($self, $peer)= @_;
	my @items= @{$self->items};
	my $weights= $self->weights;
	if ($peer->isa('Mock::Data::Set')) {
		my $peer_items= $peer->items;
		my $peer_weights= $peer->weights;
		if ($weights || $peer_weights) {
			$weights= [
				$weights?      @$weights      : (map 1, @items),
				$peer_weights? @$peer_weights : (map 1, @$peer_items),
			];
		}
		push @items, @$peer_items;
	} else {
		push @items, $peer;
		$weights= $weights && @$weights? [ @$weights, List::Util::sum0(@$weights)/@$weights ] : undef;
	}
	return Mock::Data::Set->new(
		items => \@items,
		weights => $weights,
	);
}

require Mock::Data::Util;