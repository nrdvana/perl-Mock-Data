#! /usr/bin/env perl
use Test2::V0;
use Mock::RelationalData;
use Mock::RelationalData::Table;

=head1 DESCRIPTION

This unit test checks the constructor and attributes of the Table
objects.  It does not test the larger algorithms that happen through
the table object.

=cut

my @tests= (
	[
		[
			name => 'basic_table',
			columns => [
				a => { type => 'varchar', mock => '', pk => 1 },
				b => { mock => 4 },
			]
		],
		object {
			call columns => {
				a => { name => 'a', idx => 0, type => 'varchar', mock => '', pk => 1 },
				b => { name => 'b', idx => 1, mock => 4 },
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
			name => 'mock_spec_only',
			columns => {
				a => 'x',
				b => \'#',
				c => 'z',
			},
			primary_key => 'c',
		],
		object {
			call columns => {
				a => { name => 'a', mock => 'x' },
				b => { name => 'b', mock => \'#' },
				c => { name => 'c', mock => 'z', pk => 1 },
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

my $reldata= Mock::RelationalData->new();
for (@tests) {
	my ($spec, $expected)= @$_;
	my $t= Mock::RelationalData::Table->new(parent => $reldata, @$spec);
	is( $t, $expected, $t->name );
}

done_testing;
