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
			call keys => {
				primary => {
					name => 'primary',
					cols => [ 'a' ],
					unique => 1,
				}
			};
		}
	],
	[
		[
			name => 'fill_spec_only',
			columns => {
				a => 'x',
				b => \'#',
				c => 'z',
			},
			primary_key => 'c',
		],
		object {
			call columns => {
				a => { name => 'a', fill => 'x' },
				b => { name => 'b', fill => \'#' },
				c => { name => 'c', fill => 'z', pk => 1 },
			};
			call column_order => [ 'c', 'a', 'b' ];
			call primary_key => [ 'c' ];
			call relations => {};
			call keys => {
				primary => {
					name => 'primary',
					cols => ['c'],
					unique => 1
				}
			};
		}
	],
);
for (@tests) {
	my ($spec, $expected)= @$_;
	my $t= Mock::RelationalData::Table->new(@$spec);
	is( $t, $expected, $t->name );
}

done_testing;
