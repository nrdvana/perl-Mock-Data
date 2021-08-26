#! /usr/bin/env perl
use Test2::V0;
use Mock::Data;
use Mock::Data::Plugin::Relational::Table;
sub explain { require Data::Dumper; Data::Dumper::Dumper(@_); }

=head1 DESCRIPTION

This unit test verifies that a table can generate basic columns, with or without
template rows, and that the table's indexes get updated correctly and can return
existing rows.

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
			check => { a => 1, b => 'b-default', c => 'c-default' },
		},
		'deliberate NULL' => {
			row   => { a => 2, b => undef },
			check => { a => 2, b => undef, c => 'c-default' },
		},
		'pk only' => {
			row   => { a => 3 },
			check => { a => 3, b => 'b-default', c => 'c-default' },
		},
		'dup pk' => {
			row   => { a => 3 },
			error => qr/duplicate/,
		},
		'dup pk find' => {
			row   => { a => 2 },
			find  => 1,
			check => { a => 2, b => undef, c => 'c-default' },
		},
	],
	check => object {
		call rows => [
			hash { field a => 1; etc },
			hash { field a => 2; etc },
			hash { field a => 3; etc },
		];
		call [ find_rows => { a => 2 } ] => hash { field b => undef; etc };
		call [ find_rows => { a => 3 } ] => hash { field b => 'b-default'; etc };
	},
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
			check => { a => 'first', b => 'b-default', c => 'c-default' },
			keys  => { primary => 'first', bc_key => "b-default\0c-default", c_key => 'c-default' },
		},
		'distinct row' => {
			row   => { a => 'second', b => 2, c => 2 },
			check => { a => 'second', b => 2, c => 2 },
			keys  => { primary => 'second', bc_key => "2\x002", c_key => '2' },
		},
		'dup of c' => {
			row   => { a => 'third', b => 3 },
			check => { a => 'third', b => 3, c => 'c-default' },
			keys  => { primary => 'third', bc_key => "3\0c-default", c_key => 'c-default' },
		},
		'NULL b value' => {
			row   => { a => 'fourth', b => undef, c => 3 },
			check => { a => 'fourth', b => undef, c => 3 },
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
	],
	check => object {
		call rows => [
			hash { field a => 'first'; etc },
			hash { field a => 'second'; etc },
			hash { field a => 'third'; etc },
			hash { field a => 'fourth'; etc },
		];
		call [ find_rows => { a => 'third' } ] => hash { field b => 3; etc };
		call [ find_rows => { b => 2, c => 2 } ] => hash { field a => 'second'; etc };
	},
}
);

my $mockdata= Mock::Data->new;
for my $spec (@tests) {
	my @rowtests= @{ delete $spec->{row_tests} };
	my $check= delete $spec->{check};
	my $t= Mock::Data::Plugin::Relational::Table->new($spec);
	subtest $spec->{name} => sub {
		# Iterate the $name=>\%info pairs until end of list or until next table specification
		while (@rowtests) {
			my $name= shift @rowtests;
			my ($row, $check, $find, $keys, $error)= @{shift @rowtests}{'row','check','find','keys','error'};
			my $args= { rows => [ $row ], find => $find };
			if ($error) {
				ok( !eval { $t->generate($mockdata, $args) }, "generate '$name' dies" );
				like( $@, $error, '...with correct error' );
			}
			else {
				my $added= $t->generate($mockdata, $args);
				$check= [ $check ] unless ref $check eq 'ARRAY';
				is( $added, $check, "row: $name" )
					or diag explain $added;
			}
		}
		is( $t, $check );
	};
}

done_testing;
