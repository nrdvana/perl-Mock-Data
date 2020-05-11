#! /usr/bin/env perl
use Test2::V0;
use Mock::RelationalData::Table;

my @tests= (
	[
		[
			name => 'basic_table',
			columns => [
				a => { type => 'varchar', fill => '', pk => 1 },
				b => { fill => 4 },
			]
		],
		object {
			call columns => {
				a => { name => 'a', idx => 0, type => 'varchar', fill => '', pk => 1 },
				b => { name => 'b', idx => 1, fill => 4 },
			};
			call column_order => [ 'a', 'b' ];
			call primary_key => [ 'a' ];
			call relations => {};
		}
	],
);
for (@tests) {
	my ($spec, $expected)= @$_;
	my $t= Mock::RelationalData::Table->new(@$spec);
	is( $t, $expected, $t->name );
}

done_testing;
