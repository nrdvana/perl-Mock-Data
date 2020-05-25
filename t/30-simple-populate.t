#! /usr/bin/env perl
use Test2::V0;
use Mock::RelationalData;
use Mock::RelationalData::Table;

my @tests= (
	# Table with simple primary key and non-fk columns
	{
		name => 'basic_table',
		columns => [
			a => { type => 'varchar', pk => 1 },
			b => { mock => 'b-default' },
			c => { mock => 'c-default' },
		]
	},
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
	}
);

my $reldata= Mock::RelationalData->new;
while (@tests) {
	my $spec= shift @tests;
	my $t= Mock::RelationalData::Table->new(parent => $reldata, %$spec);
	subtest $spec->{name} => sub {
		# Iterate the $name=>\%info pairs until end of list or until next table specification
		while (@tests && !ref $tests[0]) {
			my $name= shift @tests;
			my ($row, $check, $keys, $error)= @{shift @tests}{'row','check','keys','error'};
			if ($error) {
				ok( !eval { $t->add_row($row) }, "add_row '$name' dies" );
				like( $@, $error, '...with correct error' );
			}
			else {
				my $added= $t->add_row($row);
				is( $added, $check, "row: $name" );
				for my $keyname (keys %$keys) {
					my $keykey= $keys->{$keyname};
					is( $t->_row_by_key->{$keyname}, hash { field $keykey => $added; etc; }, "(key: $keyname)" );
				}
			}
		}
	};
}

done_testing;
