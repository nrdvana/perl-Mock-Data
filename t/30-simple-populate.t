#! /usr/bin/env perl
use Test2::V0;
use Mock::RelationalData;
use Mock::RelationalData::Table;

=head1 DESCRIPTION

This unit test verifies that row data gets added correctly to a single
table (no joins are considered).

The tests are given as a table constructor arguments hash, followed by
a list of row insertion tests each described by a case name with arguments
of the row and how to verify it.

(it would make sense to tree this up further, but then the indent level
would get annoying)

=cut

my @tests= (
# Table with simple primary key and non-fk columns
{
	name => 'basic_table',
	columns => [
		a => { type => 'varchar', pk => 1 },
		b => { mock => 'b-default' },
		c => { mock => 'c-default' },
	],
	row_tests => [
		# Row tests
		'pk only' => {
			row   => { a => 1 },
			check => hash { field a => 1; field b => 'b-default'; field c => 'c-default'; },
			keys  => { primary => 1 },
		},
		'deliberate NULL' => {
			row   => { a => 2, b => undef },
			check => hash { field a => 2; field b => undef; field c => 'c-default'; },
			keys  => { primary => 2 },
		},
		'pk only' => {
			row   => { a => 3 },
			check => hash { field a => 3; field b => 'b-default'; field c => 'c-default'; },
			keys  => { primary => 3 },
		},
		'dup pk' => {
			row   => { a => 3 },
			error => qr/duplicate/,
		},
	]
},
# Table with 2 unique keys and one non-unique key
{
	name => 'complex_keys',
	columns => [
		a => 'first',
		b => 'b-default',
		c => 'c-default',
	],
	keys => {
		primary => { cols => ['a'], unique => 1 },
		bc_key  => { cols => ['b','c'], unique => 1 },
		c_key   => { cols => ['c'] },
	},
	row_tests => [
		'empty row' => {
			row   => {},
			check => hash { field a => 'first'; field b => 'b-default'; field c => 'c-default'; },
			keys  => { primary => 'first', bc_key => "b-default\0c-default", c_key => 'c-default' },
		},
		'distinct row' => {
			row   => { a => 'second', b => 2, c => 2 },
			check => hash { field a => 'second'; field b => 2; field c => 2; },
			keys  => { primary => 'second', bc_key => "2\x002", c_key => '2' },
		},
		'dup of c' => {
			row   => { a => 'third', b => 3 },
			check => hash { field a => 'third'; field b => 3; field c => 'c-default' },
			keys  => { primary => 'third', bc_key => "3\0c-default", c_key => 'c-default' },
		},
		'NULL b value' => {
			row   => { a => 'fourth', b => undef, c => 3 },
			check => hash { field a => 'fourth'; field b => undef; field c => 3; },
			keys  => { primary => 'fourth', c_key => '3' },
		},
		'dup a value' => {
			row   => { b => 1, c => 1 },
			error => qr/duplicate.*?primary/,
		},
		'dup bc value' => {
			row   => { a => 2 },
			error => qr/duplicate.*?bc_key/,
		},
	]
}
);

my $reldata= Mock::RelationalData->new;
for my $spec (@tests) {
	my @rowtests= @{ delete $spec->{row_tests} };
	my $t= Mock::RelationalData::Table->new(parent => $reldata, %$spec);
	subtest $spec->{name} => sub {
		# Iterate the $name=>\%info pairs until end of list or until next table specification
		while (@rowtests) {
			my $name= shift @rowtests;
			my ($row, $check, $keys, $error)= @{shift @rowtests}{'row','check','keys','error'};
			if ($error) {
				ok( !eval { $t->add_row($row) }, "add_row '$name' dies" );
				like( $@, $error, '...with correct error' );
			}
			else {
				my $added= $t->add_row($row);
				is( $added, $check, "row: $name" );
				for my $keyname (keys %$keys) {
					my $keykey= $keys->{$keyname};
					is(
						$t->_row_by_key->{$keyname},
						hash { field $keykey => $added; etc; },
						"(key: $keyname)"
					);
				}
			}
		}
	};
}

done_testing;
