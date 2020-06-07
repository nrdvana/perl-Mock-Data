#! /usr/bin/env perl
our $rand;
BEGIN {
	# Install a global replacement for rand() that allows later tests to
	# override it on demand.
	*CORE::GLOBAL::rand= sub {
		defined $rand? $rand * ( @_? $_[0] : 1 ) : CORE::rand(@_);
	}
}
use Test2::V0 -target => 'Mock::Data::Generator::Set';

subtest constructors => \&test_constructors;
subtest weighted_distribution => \&test_weighted_distribution;

sub test_constructors {
	is(
		$CLASS->new_uniform( 'a' ),
		object {
			call items => [ 'a' ];
			call evaluate => 'a';
			call sub { shift->compile->() } => 'a';
		},
		'uniform distribution of one single item'
	);

	is(
		$CLASS->new_uniform( 'a', 'b', 'c' ),
		object {
			call items => [ 'a', 'b', 'c' ];
			call evaluate => in_set( 'a', 'b', 'c' );
		},
		'uniform distribution, several items'
	);

	is(
		$CLASS->new_weighted( 2 => 'a', 3 => 'b' ),
		object {
			call items => [ 'a', 'b' ];
			call weights => [ 2, 3 ];
			call evaluate => in_set( 'a', 'b' );
		},
		'weighted distribution'
	);
}

sub test_weighted_distribution {
	# Call weighted selection 100 times with successive values of rand() to ensure correct distribution
	no warnings 'redefine';
	my $pct100= $CLASS->new_weighted(
		10 => 'a',
		49 => 'b',
		01 => 'c',
		20 => 'd',
		20 => 'e',
	);
	my %counts;
	for my $i (0..99) {
		local $rand= $i / 100;
		++$counts{ $pct100->evaluate() };
	}
	is(
		\%counts,
		{
			a => 10,
			b => 49,
			c => 01,
			d => 20,
			e => 20,
		}
	);
}

done_testing;
