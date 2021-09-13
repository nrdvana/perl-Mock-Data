#! /usr/bin/env perl
use Test2::V0;
use Mock::Data::Table;

=head1 DESCRIPTION

This unit test checks the constructor and attributes of the Table objects,
and basic generation of rows.  It does not test the relational aspects.

=cut

my @tests= (
	[
		[
			name => 'array of columns',
			columns => [
				a => { type => 'varchar', mock => '', pk => 1 },
				b => { mock => 4 },
				{ name => 'c', type => 'varchar(16)' },
				d => '{foo}',
			]
		],
		object {
			call columns => {
				a => { name => 'a', idx => 0, type => 'varchar', mock => '', pk => 1 },
				b => { name => 'b', idx => 1, mock => 4 },
				c => { name => 'c', idx => 2, type => 'varchar', size => 16 },
				d => { name => 'd', idx => 3, mock => '{foo}' }
			};
			call column_order => [ 'a', 'b', 'c', 'd' ];
			call primary_key => [ 'a' ];
			call relationships => {};
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
			name => 'column mock spec',
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
			call relationships => {};
			call keys => {
				primary => {
					name => 'primary',
					cols => ['c'],
					unique => 1
				}
			};
		}
	],
	[
		[
			name => 'mixed cols and rels',
			columns => [
				a => '{test}',
				{ name => 'a', '1:N' => { a => 'x.id' } },
			],
		],
		object {
			call columns => {
				a => { name => 'a', mock => '{test}', idx => 0 },
			};
			call column_order => [ 'a' ];
			call primary_key => undef;
			call relationships => {
				a => { name => 'a', cardinality => '1:N',
					   cols => ['a'], peer => 'x', peer_cols => ['id'] },
			};
			call keys => {};
		}
	],
);

for (@tests) {
	my ($spec, $expected)= @$_;
	my $t= Mock::Data::Table->new(@$spec);
	is( $t, $expected, $t->name );
}

done_testing;
