#! /usr/bin/env perl
use Test2::V0;
use Mock::Data;
use Mock::Data::Relational;
sub explain { require Data::Dumper; Data::Dumper::Dumper(@_); }

=head1 DESCRIPTION

This unit test verifies the automatic creation of auto-incrementing primary key values.

=cut

subtest basic_usage => sub {
	my $mockdata= Mock::Data->new(with => 'Mock::Data::Relational');
	my $rows= $mockdata->table({
		columns => [
			id     => { mock => '{auto_increment}' },
			field1 => { mock => 1 },
			field2 => { mock => 2 },
		],
		count => 3,
	});
	is( $rows, [
		{ id => 1, field1 => 1, field2 => 2 },
		{ id => 2, field1 => 1, field2 => 2 },
		{ id => 3, field1 => 1, field2 => 2 },
	], 'simple auto_increment integer' )
		or diag explain $rows;
};

subtest counters_vs_clone => sub {
	my $mockdata= Mock::Data->new(with => 'Mock::Data::Relational');
	$mockdata->declare_schema(
		test => [ id => { mock => '{auto_increment}' } ]
	);
	is( $mockdata->table_test({ count => 2 }), [ { id => 1 }, { id => 2 } ], 'generate 1,2' );
	my $clone= $mockdata->clone;
	is( $mockdata->table_test({ count => 1 }), [ { id => 3 } ], 'generate 3' );
	is( $clone->table_test({ count => 2 }),    [ { id => 3 }, { id => 4 } ], 'generate 3,4 from clone' );
	is( $mockdata->table_test({ count => 1 }), [ { id => 4 } ], 'generate 4' );
	my $new= Mock::Data->new(with => 'Mock::Data::Relational');
	$new->declare_schema(
		test => [ id => { mock => '{auto_increment}' } ]
	);
	is( $new->table_test({ count => 1 }), [ { id => 1 } ], 'fresh counter in new mock' );
};

done_testing;
