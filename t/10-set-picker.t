#! /usr/bin/env perl
use Test2::V0 -target => 'Mock::RelationalData::SetPicker';

is(
	$CLASS->new_uniform( 'a' ),
	object {
		call items => [ 'a' ];
		call evaluate => 'a';
		call sub { shift->() } => 'a';
	},
	'uniform distribution of one single item'
);

is(
	$CLASS->new_uniform( 'a', 'b' ),
	object {
		call items => [ 'a', 'b' ];
		call evaluate => in_set( 'a', 'b' );
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

done_testing;
