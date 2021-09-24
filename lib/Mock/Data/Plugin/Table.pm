package Mock::Data::Plugin::Table;
use Mock::Data::Plugin -exporter_setup => 1;
use Carp;
use Mock::Data qw/ mock_data_subclass coerce_generator /;
use Mock::Data::Plugin::Number 'sequence';
export qw( get_generator_for_column );

# ABSTRACT: Mock::Data plugin that generates relational tables of data
# VERSION

=head1 SYNOPSIS

This L<Mock::Data> plugin supplies a collection of generators that help create
data which matches a relational schema.

The primary purpose is for unit tests, to help you fill complicated schemas
where you only want to declare the few fields that are relevant to the test,
but the schema requires many more not-null fields to have values in order to
conduct the test.

  my $mock= Mock::Data->new([qw/ Relational ... /]);
  
  # Define relational schema
  $mock->declare_tables(
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
  $mock->populate_tables(
    artist => [
      { name => 'Disaster Area', albumns => [ { ... }, { ... } ] }
    ]
  );
  
  # Then:
  
  # generate one table
  my $artist_array= $mock->artist(10);
  my $album_array= $mock->table('album',10);
  
  # generate multiple tables ( returns ->{artist} and ->{album} )
  my $table_data= $mock->tables({ rows => { artist => 10 } });

=head1 DESCRIPTION

The most obvious way to handle the problem of test data is to have a pre-defined
collection of test data declared in a .sql file and then just populate this into
an empty database before each unit test.  The primary problem with that approach
is that the test cases end up depending on many details of that test data and the
details are not visible or explained directly in the code of the unit test.
A maintenance developer seeing the project for the first time must then become
familiar with all the details of that test data set, and in a large project the
test data may become fairly large.  It also becomes a large maintenance burden to
keep the test data up to date along with all the unit tests that depend on it.

The purpose of this module is to make it easier to declare data in the unit
test so that you can keep the unit test self-contained.  Consider the following
generic example as it might be written with an external data set:

  use MyTestUtils 'my_populate_dataset1';
  my_populate_dataset1($db);
  
  my $record= $db->resultset("X")->find({ name => 'Foo1' });
  $record->interesting_method;
  my $n= $db->resultset("Y")->search({ parent_id => 1 })->count;
  is( $n, 3, 'parent 1 now has 3 Y records' );

What is special about the X record named "Foo1"? What is the significance of
parent_id of 1?  To understand the test case you must go research dataset1 to
find out.  Now consider the readability when declaring data within the unit test
itself:

  use MyTestUtils 'my_populate_data';
  my_populate_data(
    $db,
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
  
  my $record= $db->resultset("X")->find({ name => 'Foo1' });
  $record->interesting_method;
  my $n= $db->resultset("Y")->search({ parent_id => 1 })->count;
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
blanks around the data you care about.  You can implement the above example
using this module as simply as:

  sub my_populate_data {
    my ($db, @table_init)= @_;
    my $mock= Mock::Data->new(['Relational']);
    $mock->declare_tables($db); # assuming DBIx::Class::Schema object
    $mock->populate_tables({ store => $db }, @table_init);
  }

=cut

# Plugin main method, which applies plugin to a Mock::Data instance
sub apply_mockdata_plugin {
	my ($class, $mock)= @_;
	mock_data_subclass($mock, 'Mock::Data::Plugin::Table::Methods')
		->add_generators(map +("Relational::$_" => $class->can($_)), qw( table tables ));
}

=head1 GENERATORS

This plugin adds the following generators to the L<Mock::Data> instance:

=head2 table

  $rows= $mock->table( \%options );
  $rows= $mock->table( $name );
  $rows= $mock->table( $name, $rows );
  $rows= $mock->table( $name, $count );

This function runs C<generate> on one of the previously-defined tables
(from L</declare_tables>).  The name of the table can either be given as the first
positional parameter, or as 'name' within C<%options>.

See L<Mock::Data::Plugin::Relational::Table/generate> for details.

=cut

sub table {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	my $name= shift // ($params && delete $params->{name});
	
	defined $name
		or Carp::croak("'name' of table is required");
	my $table= $mock->generators->{'Table::'.$name}
		or Carp::croak("No declared table '$name'");

	$table->generate($mock, ($params? $params : ()), @_);
}

=head2 tables

  $batches= $mock->tables( \%options, $name => $rows_or_count, ... );
  
  # [
  #   { name => $name, rows => \@rows, update => \@updates },
  #   ...
  # ]

Return multiple tables of data, grouped in batches in the order that they should be inserted.
If the schema contains circular references (such as "the userid who last updated this user row")
the rows will be sorted in an order that allows those to insert cleanly, unless there is a
circular dependency in which case the C<@updates> are used to patch-up the records afterward.
C<@updates> are each a hashref of a partial row, containing the fields for the primary key and
the fields that need to be updated.  You can apply this using DBIC's
C<< $rs->find($row)->update($row) for @updates >>.  Also note that more than one batch may
occur for the same table.

Available C<%options>:

=over

=item C<store>

An instance of L<Mock::Data::Plugin::Relational::RowCache> (or hashref of constructor
parameters for one) or instance of L<DBIx::Class::Schema> where generated rows should be
cached/stored, and which should be consulted any time the algorithm wants to find an existing
record by some key.

If not specified, a default RowCache is created within the C<Mock::Data> instance.

=item C<as_objects>

If you reference a C<DBIx::Class::Schema> in C<store>, then C<DBIx::Class> row objects are
getting created as this method runs.  Set this option to true to return those row objects
instead of the hashrefs that would normally be returned.  It is an error to ask for row objects
unless a C<DBIx::Class::Schema> was provided.

=back

For each pair of positional arguments given, the first will be the name of a table in the
schema, and the second is either a count of rows, or an arrayref of row data that will be
filled in.

=cut

sub tables {
	
}

=head2 auto_unique

  $random_id= $mock->auto_unique({ table => $table_instance, column => \%col_info })

This generator returns some random value appropriate for the column which is unique from any
other that has been generated for this column of this table.  The type of the data generated
will match the C<type> of the column, or an integer if the C<type> is not known.

=over

=item table

An instance of L<Mock::Data::Plugin::Relational::Table>

=item column

A hashref of column info according to L<Mock::Data::Plugin::Relational::Table/columns>.

=item source

A generator from which to pull values.  If not provided, one will be chosen according to
the C<type> of the column.

=item max_attempts

The maximum number of random values that will be generated before giving up on finding a
unique value. (after which, the generator dies.) The default is 10.

=back

=cut

sub auto_unique {
	my ($mockdata, $args)= @_;
	my ($table, $column, $source, $n)= @{$args}{qw/ table column source max_attempts /};
	$source ||= _decide_auto_unique_source($column);
	my $key= $table->has_unique_key($column->{name});
	for (1.. ($n || 10)) {
		my $val= $mockdata->$source;
		if ($key) {
			return $val unless $table->find_rows_by_key($key, { $column->{name} => $val });
		} else {
			no warnings 'uninitialized';
			return $val unless grep $_->{$column->{name}} eq $val, @{ $table->rows };
		}
	}
	croak "Failed to generate unique value for ".$table->name." $column->{name} after $n attempts";
}

sub _decide_auto_unique_source {
	...
}

=head2 numeric

  $mockdata->numeric({ col => $c })

This generator returns a random number within the number of digits and precision specified
for the column.

=head1 METHODS

The following methods are added to the Mock::Data instance when using this plugin:

=cut

# Methods are defined in this file
@Mock::Data::Plugin::Table::Methods::ISA= ( 'Mock::Data' );
$INC{'Mock/Data/Plugin/Table/Methods.pm'}= __FILE__;
*Mock::Data::Plugin::Table::Methods::declare_tables= *declare_tables;
*Mock::Data::Plugin::Table::Methods::set_column_mock= *set_column_mock;
*Mock::Data::Plugin::Table::Methods::get_generator_for_column= *get_generator_for_column;
*Mock::Data::Plugin::Table::Methods::table= *table;
*Mock::Data::Plugin::Table::Methods::tables= *tables;

=head2 declare_tables

  $mock->declare_tables($dbic_schema, ...);
  $mock->declare_tables($dbic_source, ...);
  $mock->declare_tables(\%table_attributes, ...);
  $mock->declare_tables($table_name => \%table_attributes, ...);
  $mock->declare_tables($table_name => \@column_list, ...);

Define one or more tables.  This function allows a variety of input: L<DBIx::Class::Schema>
objects import every Source of the schema as a table, L<DBIx::Class::ResultSource> objects
import a single table, a hashref is used as the direct constructor arguments for a
L<Mock::Data::Plugin::Relational::Table>, and a scalar followed by an array or hashref are considered
to be a table name and its column specification.

The table name must be unique.  If you wish to replace a table, prefix the table name with
a C<'-'> or add C<< replace => 1 >> to the table attribute hash.

  $schema->declare( -Artist => $new_definition );

=cut

sub declare_tables {
	my $self= shift;
	while (@_) {
		my $thing= shift;
		my $replace;
		my %ctor;
		if (!ref $thing) {  # thing was a name in the form ($thing => $value)
			$replace= ($thing =~ s/^-//);
			if (ref $_[0] eq 'ARRAY') {
				%ctor= ( columns => shift );
			} elsif (ref $_[0] eq 'HASH') {
				%ctor= %{+shift};
			} else {
				%ctor= %{Mock::Data::Table->coerce_attributes(shift)};
			}
			$ctor{name}= $thing;
		}
		# Is it a DBIx::Class::Schema? then iterate all sources
		elsif (ref($thing)->isa('DBIx::Class::Schema')) {
			unshift @_, map +($_ => $thing->source($_)), $thing->sources;
			next;
		}
		else {
			%ctor= %{Mock::Data::Table->coerce_attributes(shift)};
		}
		$replace ||= delete $ctor{replace};
		my $table= Mock::Data::Table->new(\%ctor);
		my $gen_name= 'Table::'.$table->name;
		croak "Table generator '$gen_name' was already defined"
			if $self->generators->{$gen_name} && !$replace;
		$self->generators->{$gen_name}= $table;
		$self->generators->{$table->name} //= $table;
	}
	$self;
}

=head2 set_column_mock

You can declare the C<mock> attribute on each column you define in L</define_table>, however if
you loaded your schema from a C<DBIx::Class::Schema> you can't redefine the table, and probably
just want to add the C<mock> attribute to the existing columns.  This method does that.

  $mockdata->set_column_mock(
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

=head2 get_generator_for_column

  my $generator= $mock->get_generator_for_column(\%col_info);
  my $generator= $mock->get_generator_for_column($table, $col);

Given a hashref of L<column info|Mock::Data::Table/columns>, return a generator that can return
valid values for this column.  Alternately, you can pass a table name (or table reference) and
column name (or column reference).  In some cases, the table is required to give the most
correct generator.

=cut

sub get_generator_for_column {
	my ($mock, $col, $table)= @_ == 2? @_ : @_[0,2,1];
	if (defined $table && !ref $table) {
		my $t= $mock->generators->{"Table::$table"} // $mock->generators->{$table};
		defined $t && $t->isa('Mock::Data::Table')
			or croak "No such table $table";
		my $c= ref $col? $col : $t->columns->{$col}
			or croak "No such column $t->{name}.$col";
		($table, $col)= ($t, $c);
	}

	return coerce_generator($col->{mock})
		if defined $col->{mock};

	if ($col->{auto_increment}) {
		my $seq_name= $table? "$table->{name}.$col->{name}"
			: $col->{name}? 0+$col . ".$col->{name}"
			: 0+$col;
		return Mock::Data::GeneratorSub->new(sub { sequence(shift, $seq_name) })
	}

	if (my $def= $col->{defalt_value}) {
		return sub { $def }
			unless ref $def;
		# maybe try to parse SQL functions in scalar ref?
	}

	return Mock::Data::Plugin::SQLTypes::generator_for_type($mock, $col->{type})
		if $col->{type};

	return undef;
}

=head2 populate_schema

  $reldata->populate_schema(table1 => [ \%record1, \%record2, ... ], ...);
  $reldata->populate_schema(table1 => [ \@columns, \@record1, \@record2 ], ...);

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

require Mock::Data::Table;
require Mock::Data::Plugin::SQLTypes;
1;

=head1 SEE ALSO

=over

=item *

L<Cheater>

=item *

L<Data::Faker>

=item *

L<Mock::Populate>

=back
