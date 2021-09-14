#! /usr/bin/env perl
use Test2::V0;
use FindBin;
use lib "$FindBin::RealBin/lib";
use MockDBIxClass;
use Mock::Data;
use Mock::Data::Table;
use Mock::Data::Plugin::Number 'sequence';

=head1 DESCRIPTION

This unit test checks the constructor and attributes of the Table objects,
and basic generation of rows.  It does not test the relational aspects.

=cut

subtest constructor => sub {
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
					a => { name => 'a', cardinality => '1:N', null => 0,
						   cols => ['a'], peer => 'x', peer_cols => ['id'] },
				};
				call keys => {};
			}
		],
		[
			[MockDBIxClass::ResultSource->new({
				name => 'from_schema_ResultSource',
				columns => [
					id   => { data_type => 'integer', is_auto_increment => 1, is_nullable => 0 },
					name => { data_type => 'varchar', size => 64 },
					val  => { data_type => 'numeric', size => [8,2],          is_nullable => 1 },
				],
				keys => {
				},
				relationships => {
				},
			})],
			object {
				call name => 'from_schema_ResultSource';
				call columns => {
					id   => { name => 'id',   type => 'integer', auto_increment => 1,      idx => 0 },
					name => { name => 'name', type => 'varchar', size => 64,               idx => 1 },
					val  => { name => 'val',  type => 'numeric', size => [8,2], null => 1, idx => 2 },
				};
				call column_order => ['id','name','val'],
			}
		],
	);

	for (@tests) {
		my ($spec, $expected)= @$_;
		my $t= Mock::Data::Table->new(@$spec);
		is( $t, $expected, $t->name );
	}
};

subtest simple_rows => sub {
	my $mock= Mock::Data->new();
	my $table= Mock::Data::Table->new(
		name => 'basic_table',
		columns => [
			a => { pk => 1, mock => sub{ sequence(shift,'basic_table.a') } },
			b => { mock => 'b-default' },
			c => { mock => 'c-default' },
		],
	);
	my @row_tests= (
		# Row tests
		{
			name => 'pk only',
			params => { rows => [{}] },
			check => [{ a => 1, b => 'b-default', c => 'c-default' }],
		},
		{
			name => 'deliberate NULL',
			params => { rows => [{ b => undef }] },
			check => [{ a => 2, b => undef, c => 'c-default' }],
		},
		{
			name => 'pk only',
			params => { rows => [{}] },
			check => [{ a => 3, b => 'b-default', c => 'c-default' }],
		},
		{
			name => 'dup pk',
			params => [{ rows => [{ a => 3 }] }],
			error => qr/duplicate/i,
		},
		{
			name => 'dup pk find',
			params => [{ find => 1, rows => [{ a => 2 }] }],
			check => [{ a => 2, b => undef, c => 'c-default' }],
		},
	);
	for (@row_tests) {
		my ($name, $params, $check, $errcheck)= @{$_}{'name','params','check','error'};
		my ($result, $err);
		{
			local $@;
			$result= eval { $table->generate($mock, ref $params eq 'ARRAY'? @$params : $params) };
			$err= $@;
		}
		is( $result, $check, $name ) if defined $check;
		like( $err, $errcheck, $name ) if defined $errcheck || !defined $result;
	}
};

subtest complex_keys => sub {
	# Table with 2 unique keys and one non-unique key
	my $mock= Mock::Data->new();
	my $table= Mock::Data::Table->new(
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
	);
	my @row_tests= (
		'empty row' => {
			row   => {},
			check => { a => 'first', b => 'b-default', c => 'c-default' },
			keys  => { primary => 1, bc_key => 1, c_key => 1 },
		},
		'distinct row' => {
			row   => { a => 'second', b => 2, c => 2 },
			check => { a => 'second', b => 2, c => 2 },
			keys  => { primary => 1, bc_key => 1, c_key => 1 },
		},
		'dup of c' => {
			row   => { a => 'third', b => 3 },
			check => { a => 'third', b => 3, c => 'c-default' },
			keys  => { primary => 1, bc_key => 1, c_key => 1 },
		},
		'NULL b value' => {
			row   => { a => 'fourth', b => undef, c => 3 },
			check => { a => 'fourth', b => undef, c => 3 },
			keys  => { primary => 1, c_key => 1 },
		},
		'dup a value' => {
			row   => { b => 1, c => 1 },
			error => qr/duplicate.*?primary/i,
		},
		'dup bc value' => {
			row   => { a => 2 },
			error => qr/duplicate.*?bc_key/i,
		},
	);
	my $name;
	for (@row_tests) {
		ref or $name=$_, next;
		my ($row, $check, $keys, $errcheck)= @{$_}{'row','check','keys','error'};
		my ($result, $err);
		{
			local $@;
			$result= eval { $table->generate($mock, [$row]) };
			$err= $@;
		}
		is( $result, [$check], $name ) if defined $check;
		like( $err, $errcheck, $name ) if defined $errcheck || !defined $result;
		for (!$keys? () : keys %$keys) {
			my @rows= $mock->generator_state->{'Table::data'}->find_rows($table, $row, $table->keys->{$_});
			is( $rows[-1], $keys->{$_}? exact_ref($row) : undef, "row indexed by $_" );
		}
	}
};

subtest has_many => sub {
	my $mock= Mock::Data->new({
		plugins => ['SQLTypes'],
		generators => {
			album => Mock::Data::Table->new({
				name => 'album',
				columns => [
					id   => { auto_increment => 1, mock => '{sequence album.id}' },
					name => { type => 'varchar' },
					artist_id => { fk => 'artist.id' },
				],
			}),
			artist => Mock::Data::Table->new({
				name => 'artist',
				columns => [
					id   => { auto_increment => 1, mock => '{sequence artist.id}' },
					name => { type => 'varchar' },
				],
				relationships => {
					albums => { '1:N' => { id => 'album.artist_id' } }
				}
			})
		}
	});
	my $result= $mock->call(artist => [
		{ name => 'Symphony X', albums => [
			{ name => 'The Odyssey' },
			{ name => 'Paradise Lost' }
		]}
	]);
	is(
		$result,
		[{ id => 1, name => 'Symphony X', albums => [
			{ id => 1, name => 'The Odyssey', artist_id => 1 },
			{ id => 2, name => 'Paradise Lost', artist_id => 1 },
		]}],
		'Artist with two albums'
	);
};

done_testing;
