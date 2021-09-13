#! /usr/bin/env perl
use Test2::V0;
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

done_testing;
