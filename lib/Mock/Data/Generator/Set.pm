package Mock::Data::Generator::Set;
use strict;
use warnings;

=head1 SYNOPSIS

  use Mock::Data::Generator 'uniform_set', 'weighted_set';
  $gen= uniform_set( 'a', 'b', 'c', 'd' )->compile;
  $value= $gen->($mockdata);   # 25% chance of each of the items
  
  $gen= weighted_set( 1 => 'a', 9 => 'b' )->compile;
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

Standard Moo constructor, accepting attribute initial values.  The values of C<items>
must be scalars or coderefs (generators).

=head2 new_uniform

  $picker= $class->new_uniform(@items);

Construct a C<SetPicker> from a list of items, where each item may be a template or
other valid specification for C<compile_generator>.  Each item is given a uniform
probability.

=head2 new_weighted

  $picker= $class->new_weighted($weight => $item, ...);

Construct a C<SetPicker> from a list of pairs of weight and item.  Item may be a template
or other valid specification for C<compile_generator>.  The 

=cut

sub new_uniform {
	my $class= shift;
	my $items= @_ == 1 && ref $_[0] eq 'ARRAY'? shift : [@_];
	$class->new(items => $items);
}

sub new_weighted {
	my $class= shift;
	my (@weights, @items);
	while (@_) {
		push @weights, shift;
		push @items, shift;
	}
	$class->new(items => \@items, weights => \@weights);
}

=head2 evaluate

  $val= $picker->evaluate($datagen, \%args);

Return one random item from the set.  This should be called with the reference
to the L<Mock::DataGen> and optional named arguments. (as for any generator)

=cut

sub evaluate {
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
	my $cmp_items= $self->{_compiled_items}
		||= $self->_build__compiled_items($_[0]);
	$pick= $cmp_items->[$pick];
	return ref $pick? $pick->(@_) : $pick;
}

sub _compiled_items {
	$_[0]{_compiled_items} # can't lazy-build without Mock::Data instance
}

# not an actual lazy builder
sub _build__compiled_items {
	my ($self, $mockdata)= @_;
	defined $mockdata or die "Need Mock::Data parameter";
	my @compiled= @{ $self->items };
	for (@cmp) {
		# don't bother compiling plain strings into generators
		$_= $mockdata->compile_generator($_)
			if ref $_ or index($_, '{') >= 0;
	}
	\@compiled;
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

1;
