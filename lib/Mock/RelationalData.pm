package Mock::RelationalData;
use Moo 2;

=head1 SYNOPSIS

This module assists you with creating data that matches a relational schema,
with a minimal amount of manually-specified data.  This is primarily useful for
writing unit tests of complicated schemas where you only want to declare the
few fields that are relevant to the test, but the schema requires many more
not-null fields to have values in order to conduct the test.

  my $reldata= Mock::RelationalData->new;
  
  # Define custom mock data generators
  $reldata->add_generator("words" => ...);
  
  # Define relational schema
  $reldata->define_schema(
    # you can import a whole DBIC schema
    $dbic_schema,
    
    # or import specific tables from a DBIC schema
    $dbic_result_source,
    
    # or define tables on your own
    artist => [
      id        => { type => 'integer',     default => 'auto_inc', pk => 1 },
      name      => { type => 'varchar(99)', default => 'words' },
      formed    => { type => 'datetime' },
      disbanded => { type => 'datetime', null => 1 },
    ],
    album => [
      id        => { type => 'integer',     default => 'auto_inc', pk => 1 },
      artist_id => { type => 'integer',     fk => [artist => 'id'] },
      name      => { type => 'varchar(99)', default => 'words' },
      released  => { type => 'datetime',    null => 1 },
    ],
  );
  
  # Then create a record
  $reldata->add_records(album => { name => 'Test' });
  
  # has the effect of: 
  # push @artist, [ my $artist_id= auto_inc(...), words(...), datetime(...), undef ];
  # push @album,  [ auto_inc(...), $artist_id, varchar(...), undef ];
  
  # Then use the data:
  for my $dataset ($reldata->get_populate_sequence(as_array => 1)) {
    $dbic_schema->resultset($dataset->{table_name})->populate($dataset->{rows});
  }

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

The purpose of this module is to make it so easy to declare data *in* the unit
test that you can keep the unit test self-contained.  Consider the following
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

has tables     => ( is => 'rw' );

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

sub define_table {
	my $self= shift;
	my $table= Mock::RelationalData::Table->new(@_ == 1 && ref $_[0] eq 'HASH'? %{$_[0]} : @_);
	croak "Table ".$table->name." was already defined"
		if $self->tables->{$table->name};
	$self->tables->{$table->name}= $table;
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
