package Mock::RelationalData::SetPicker;
use Moo;
use Mock::RelationalData::Gen 'compile_generator';

=head1 SYNOPSIS

  $picker= Mock::RelationalData::SetPicker
	->new_uniform( 'a', 'b', 'c', 'd' );
  $value= $picker->();   # 25% chance of each of the items
  
  $picker= Mock::RelationalData::SetPicker
	->new_weighted( 'a' => 1, 'b' => 9 );
  $value= $picker->();   # 10% chance of 'a', 90% chance of 'b'
  
  $picker= Mock::RelationalData::SetPicker
	->new_uniform( 'a', [ 'b', 'c' ] );
  $value= $picker->();   # 50% chance of 'a', 25% chance of 'b', 25% chance of 'c'

=head1 DESCRIPTION

This object selects a random element from a list.  All items are given probability
unless C<weights> are specified to change the probability.  The items of the list
may be templates (as per L<Mock::RelationalData::Gen/compile_generator>) which means
they may also be arrayrefs that turn into a nested C<SetPicker> object.

The object overloads the method call operator, so it can act as a coderef (and
thus a generator)

=head1 ATTRIBUTES

=head2 items

The arrayref of items which can be returned by this generator

=head2 weights

An optional arrayref of values, one value per element of C<items>.  The weight values
are on an arbitrary scale chosen by the user, such that the sum of them adds up to 100%.

=cut

has items       => is => 'rw', required => 1, coerce => \&_coerce_items;
has weights     => is => 'rw';
has _odds_table => is => 'lazy';

=head1 METHODS

=head2 new

Standard Moo constructor, accepting attribute initial values.  The values of C<items>
must be scalars or coderefs.  (i.e. the output of C<compile_generator>)

=head2 new_uniform

  $picker= Mock::RelationalData::SetPicker->new_uniform(@items);

Construct a C<SetPicker> from a list of items, where each item may be a template or
other valid specification for C<compile_generator>.  Each item is given a uniform
probability.

=head2 new_weighted

  $picker= Mock::RelationalData::SetPicker->new_uniform($weight => $item, ...);

Construct a C<SetPicker> from a list of pairs of weight and item.  Item may be a template
or other valid specification for C<compile_generator>.

=cut

sub new_uniform {
	my $class= shift;
	my $items= @_ == 1 && ref $_[0] eq 'ARRAY'? shift : [ @_ ];
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

sub _coerce_items {
	my $items= shift;
	for (@$items) {
		$_= compile_generator($_) if ref $_ or index($_, '{') >= 0;
	}
	$items;
}

=head2 evaluate

  $val= $picker->evaluate($reldata, \%args);

Return one random item from the set.  This should be called with the reference
to the RelationalData and optional named argument set for any generator.

=cut

use overload '&{}' => sub { my $self= shift; sub { $self->evaluate(@_) } };

sub evaluate {
	my $self= shift;
	my $items= $self->items;
	my $pick;
	if (!$self->weights) {
		$pick= $items->[ rand( scalar @$items ) ];
	} else {
		# binary search for the random number
		my $tbl= $self->_odds_table;
		my ($min, $max, $r)= (0, $#$items, rand);
		while ($min+1 < $max) {
			my $mid= int(($max-$min)/2);
			if ($r < $tbl->[$mid]) { $max= $mid-1; }
			else { $min= $mid; }
		}
		$pick= $items->[ ($max > $min && $tbl->[$max] <= $r)? $max : $min ];
	}
	return ref $pick? $pick->(@_) : $pick;
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
