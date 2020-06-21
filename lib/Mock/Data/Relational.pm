package Mock::Data::Relational;
use strict;
use warnings;
use Mock::Data qw/ mock_data_subclass /;

=head1 SYNOPSIS

This module assists you with creating data that matches a relational schema,
with a minimal amount of manually-specified data.  This is primarily useful for
writing unit tests of complicated schemas where you only want to declare the
few fields that are relevant to the test, but the schema requires many more
not-null fields to have values in order to conduct the test.

  my $mockdata= Mock::Data->new([qw/ Relational ... /])->new;
  
  # Define relational schema
  $mockdata->declare_schema(
    # you can import a whole DBIC schema
    $dbic_schema,
    
    # or import specific tables from a DBIC schema
    $dbic_result_source,
    
    # or define tables on your own
    artist => [
      id        => { type => 'integer',     mock => 'auto_inc', pk => 1 },
      name      => { type => 'varchar(99)', mock => 'words' },
      formed    => { type => 'datetime' },
      disbanded => { type => 'datetime', null => 1 },
      albums    => { cardinality => '1:N', colmap => { id => 'album.artist_id' } },
    ],
    album => [
      id        => { type => 'integer',     mock => 'auto_inc', pk => 1 },
      artist_id => { type => 'integer',     fk => 'artist.id' },
      name      => { type => 'varchar(99)', mock => 'words' },
      released  => { type => 'datetime',    null => 1 },
    ],
  );
  
  # Optionally define static data
  $mockdata->declare_reldata(
    artist => [
      { name => 'Disaster Area', albumns => [ { ... }, { ... } ] }
    ]
  );
  
  # Then:
  
  # generate one table
  my $artist_array= $mockdata->reldata({ rows => 10 }, 'artist');
  
  # generate multiple tables ( returns ->{artist} and ->{album} )
  my $table_data= $mockdata->reldata({ rows => { artist => 10 } });

=head1 DESCRIPTION

The most obvious way to handle the problem of test data is to have a pre-defined
collection of test data declared in a .sql file and then just populate this into
an empty database before each unit test.  The primary problem with that approach
is that the test cases end up depending on many details of that test data and the
details are not visible or explained directly in the code of the unit test.
A maintenance developer seeing the project for the first time must then become
familiar with all the details of that test data set, and in a large project, the
test data may become fairly large.  It also becomes a large maintenance burden to
keep the test data and all the unit tests that depend on it up to date.

The purpose of this module is to make it easier to declare data in the unit
test so that you can keep the unit test self-contained.  Consider the following
generic example as it might be written with an external data set:

  use MyTestUtils 'my_populate_dataset1';
  my_populate_dataset1($schema);
  
  my $record= $schema->resultset("X")->find({ name => 'Foo1' });
  $record->interesting_method;
  my $n= $schema->resultset("Y")->search({ parent_id => 1 })->count;
  is( $n, 3, 'parent 1 now has 3 Y records' );

Here, to understand the test case, you must go research dataset1 to find out
about the data of the row where C<< name = "Foo1" >>, and what C<parent_id> of
1 means.  Now consider the readability when declaring data within the unit test
itself:

  use MyTestUtils 'my_populate_data';
  my_populate_data(
    $schema,
    A => [
      { id => 1 },
    ],
    X => [
      { name => 'Foo1', a_id => 1, relevant_attribute => 3 },
    ],
    Y => [
      { parent_id => 1 },
    ]
  );
  
  my $record= $schema->resultset("X")->find({ name => 'Foo1' });
  $record->interesting_method;
  my $n= $schema->resultset("Y")->search({ parent_id => 1 })->count;
  is( $n, 3, 'parent 1 now has 3 Y records' );

Now you can clearly see that X relates to A, and Y relates to A, and there was
one Y record in the schema before calling C<interesting_method>, and 3 records
in table Y afterward.  Having the test data right next to the test case makes
it more readable.

But of course, most schemas can't declare records that simply!  In a long-lived
system, table A probably has a dozen not-null fields, and probably a few dozen
other related objects with foreign key constraints, and in order to populate
this tiny bit of data you'd have to specify dozens of other fields and records,
making an unreadable mess of details.

This module solves that problem by generating mock data to fill in all the
blanks around the data you care about.

=cut

sub apply_mockdata_plugin {
	my ($class, $mockdata)= @_;
	$mockdata->add_generators({
		reldata => \&reldata,
	});
	return mock_data_subclass($mockdata, 'Mock::Data::Relational::Methods');
}

=head1 GENERATORS

This plugin adds the following generators to the L<Mock::Data> instance:

=head2 table

  $rows= $mockdata->table( \%named_args );
  $rows= $mockdata->table( \%named_args, $name => $rows_or_count );

This function returns one table of data, as an arrayref.  Each element of the arrayref
is a hashref, where the fields are defined either from named arguments to the generator,
or by a pre-declared schema.

The following named arguments can be given:

=over

=item C<name>

The name of the pre-declared table to use.  This is required unless you specify the fields
directly.

=item C<fields>

An arrayref or hashref of field or definitions.
See L<Mock::Data::Relational::Table/fields> for a description of a field,
or L<Mock::Data::Relational::Table/coerce_field> for the different shorthand
notations you can use.

These elements may contain relationship shorthand notation, and will be automatically
sorted into that category.

=item C<relationships>

An arrayref or hashref of relationships to other tables.
See L<Mock::Data::Relational::Table/relationships> for a description of a relationship,
or L<Mock::Data::Relational::Table/coerce_relationship> for the different shorthand
notations you can use.

=item C<keys>

An arrayref or hashref of keys which can be used to identify distinctness of rows.
See L<Mock::Data::Relational::Table/keys> for a description of a key,
or L<Mock::Data::Relational::Table/coerce_key> for the different shorthand
notations you can use.

=item C<rows>

An arrayref of row hashrefs.  Each will be used as a template of literal values around which
the rest of the missing fields will be inserted.

=item C<find>

Boolean, whether to return existing rows when one of C<rows> specifies a unique key that
was already generated.  If this is false (the default) and the row has a conflictig unique
key, it will result in an exception.

=item C<count>

The number of rows to generate.  Defaults to 1.  This cannot be given with C<rows>.

=item C<via_relationship>

  via_relationship => [ $table, $row, $rel_name ]

This describes a row of another table and a relationship that is being followed in order to
produce these rows.  The generated rows may receive additional default values from the original
row according to the columns of the relationship.

=back

If a first positional argument is present, it is treated as C<fields> if it is a hashref
or arrayref, or C<name> if it is a scalar.

If a second positional argument is present, it is treated as C<rows> if it is an arrayref,
or C<count> if it is a scalar.

Examples:

  # generate one table, returning array of 10 records of the form
  # {
  #   name => $mockdata->words({size => 99}),
  #   value => $mockdata->integer({size => 4})
  # }
  $name_value_array= $mockdata->table({
    fields => [
      name => { mock => '{words 64}' },
      value => { type => 'numeric(4,0)' },
    ],
    count => 10
  });

  # If the relation was pre-declared as "name_val", you can reference it:
  $name_value_array= $mockdata->table({ count => 10 }, 'name_val' );

=cut

sub table {
	my $mockdata= shift;
	my $named_args= shift if ref $_[0] eq 'HASH';
	my $name= shift;
	my ($rows, $count)= !@_? (undef,undef) : ref $_[0]? (shift, undef) : (undef, shift);
	my $table;
	my $via;

	# Fetch or construct the table specification
	if (defined $named_args) {
		my %args= %$named_args;
		$name= delete $args{name} unless defined $name;
		$rows= delete $args{rows} unless defined $rows;
		$count= delete $args{count} unless defined $count;
		$via_relationship= delete $args{via_relationship};
		if ($args{fields}) {
			$table= Mock::Data::Relational::Table->new(parent => $mockdata, %args);
		}
	}
	if ($table) {
		$mockdata->generator_state->{__PACKAGE__}{tables}{$name}= $table
			if defined $name;
	}
	elsif (defined $name) {
		$table= $mockdata->generator_state->{__PACKAGE__}{tables}{$name}
			or croak "No declared table 'name'";
	} else {
		croak "Require 'name' or 'fields' in order to define the table";
	}

	# Create or fill-in the rows requested
	if ($rows) {
		$table->generate_row($_) for @$rows;
	} else {
		$count= 1 unless defined $count;
		$rows= [];
		push @$rows, $table->generate_row for 1..$count;
	}
	return $rows;
}

=head2 tables

  my $table_set= $mockdata->tables( \%named_args, $name => $rows_or_count, ... )

Return multiple tables of data, in a hashref by table name.

The named arguments can contain the following:

=over

=item schema

A hashref of table name to table specification, each matching the description in L</table>.

=back

For each pair of positional arguments given, the first will be the name of a table in the
schema, and the second is either a count of rows, or an arrayref of row data that will be
filled in.

=cut

sub tables {
	
}

=head2 declare_schema

  $reldata->define_schema($dbic_schema, ...);
  $reldata->define_schema($dbic_source, ...);
  $reldata->define_schema(\%table_attributes, ...);
  $reldata->define_schema($table_name => \%columns, ...);

Define one or more tables.  This function allows a variety of input: L<DBIx::Class::Schema>
objects import every Source of the schema as a table, L<DBIx::Class::ResultSource> objects
import a single table, a hashref is used as the direct constructor arguments for a
L<Mock::RelationalData::Table>, and a scalar followed by an array or hashref are considered to
be a tbale name and its column specification.

The table name must be unique; attempts to define a table twice will throw an exception.

=cut

sub define_schema {
	my $self= shift;
	while (@_) {
		my $thing= shift;
		if (!ref $thing) {
			my $columns= shift || croak "Expected column arrayref or hashref following '$thing'";
			$self->define_table(name => $thing, columns => $columns);
		}
		elsif (ref $thing eq 'HASH') {
			$self->define_table(%$thing);
		}
		elsif (ref($thing)->isa('DBIx::Class::Schema')) {
			$self->define_table(_dbic_rsrc_to_table_spec($thing->source($_)))
				for $thing->sources;
		}
		elsif (ref($thing)->isa('DBIx::Class::ResultSource')) {
			$self->define_table(_dbic_rsrc_to_table_spec($thing));
		}
		else {
			croak "Don't know what to do with '$thing' (not a table name, hashref, or DBIC object)";
		}
	}
}

=head2 define_table

  $reldata->define_table( %attrs );

This is a shortcut for creating instances of L<Mock::RelationalData::Table> and assigning them
to the L</tables> hashref.  If a table by this name already exists, it throws an error.

=cut

sub define_table {
	my $self= shift;
	my $table= Mock::RelationalData::Table->new(@_ == 1 && ref $_[0] eq 'HASH'? %{$_[0]} : @_);
	croak "Table '".$table->name."' was already defined"
		if $self->tables->{$table->name};
	$self->tables->{$table->name}= $table;
}

=head2 set_column_mock

You can declare the C<mock> attribute on each column you define in L</define_table>, however if
you loaded your schema from a C<DBIx::Class::Schema> you can't redefine the table, and probably
just want to add the C<mock> attribute to the existing columns.  This method does that.

  $reldata->set_column_mock(
    table1 => {
      col1 => $mock_spec,
      col2 => $mock_spec,
    },
    table2 => { ... },
    ...
  );

=cut

sub set_column_mock {
	my $self= shift;
	while (my ($table_name, $colmock)= splice @_, 0, 2) {
		my $table= $self->tables->{$table_name} or croak "Table '$table_name' is not declared";
		for my $col (keys %$colmock) {
			defined $table->columns->{$col} or croak "Column '$table_name'.'$col' does not exist";
			$table->columns->{$col}{mock}= $colmock->{$col};
		}
		$table->_clear_mock_cache;
	}
}

sub add_generator {
	my ($self, $name, $spec)= @_;
	$self->generators->{$name}= $self->compile_generator($spec);
}

sub compile_generator {
	my $self= shift;
	Mock::RelationalData::Gen::compile_generator(@_);
}

sub default_generator_for_column {
	my ($self, $table, $col)= @_;
	return $self->compile_generator($col->{mock});
		if exists $col->{mock};

	return $self->generators->{int_seq}
		if $col->{is_auto_increment} && defined $self->generators->{int_seq};
	
	if (defined $col->{data_type}) {
		my ($base_type)= $col->{data_type} =~ /^(\w+)/;
		my $gen= $self->generators->{"data_type_$base_type"};
		return $gen if defined $gen;
	}

	return undef;
}

=head2 populate

  $reldata->populate(table1 => [ \%record1, \%record2, ... ], ...);
  $reldata->populate(table1 => [ \@columns, \@record1, \@record2 ], ...);

Like L<DBIx::Class::ResultSource/populate>, this adds rows to tables (in memory).
The records can either be specified as an array of hashrefs, or as an array of arrayrefs where
the first arrayref lists the column names and the remainder list the column values in the same
order.

This will die if the new records violate a unique key on the table.

Note that this modifies the table objects, so if you want to re-use the declared schema for
other data sets, you should L</clone> it first.

=cut

sub populate {
	my $self= shift;
	my @ret;
	while (@_) {
		my $tname= shift;
		my $table= $self->tables->{$tname}
			or croak "No such table '$tname'";
		$table->populate(shift);
	}
	return @ret;
}

sub _dbic_rsrc_to_table_spec {
	my $rsrc= shift; # DBIC ResultSource
	return (
		name => $rsrc->name,
		column_order => [ $rsrc->columns ],
		columns => $rsrc->columns_info,
		primary_key => [ $rsrc->primary_columns ],
		relations => {
			map { $_ => _dbic_rel_to_relation_spec($rsrc->relationship_info($_)) }
				$rsrc->relationships
		},
	);
}

sub _dbic_rel_to_relation_spec {
	my $dbic_rel= shift;
	$dbic_rel; # TODO
}

1;
