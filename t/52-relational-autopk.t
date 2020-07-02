#! /usr/bin/env perl
use Test2::V0;
use Mock::Data;
use Mock::Data::Relational;
sub explain { require Data::Dumper; Data::Dumper::Dumper(@_); }

=head1 DESCRIPTION

This unit test verifies the automatic creation of auto-incrementing primary key values.

=cut

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

done_testing;
