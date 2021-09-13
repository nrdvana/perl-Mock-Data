package Mock::Data::Table;
use strict;
use warnings;
use Carp 'croak';
use Scalar::Util;
use List::Util;
use Mock::Data::Util 'coerce_generator';
require Mock::Data::Plugin::Table::TableData;
require Mock::Data::Generator;
our @ISA= ( 'Mock::Data::Generator' );

# ABSTRACT: Object representing one defined schema table
# VERSION

=head1 SYNOPSIS

  my $table= Mock::Data::Table->new({
    name => 'Artist',
    columns => [
      { name => 'id', type => 'integer' },
      { name => 'name', type => 'varchar', size => 100 },
    ],
    relationships => [
      ...
    ]
  });
  
  # generate rows
  $rows= $table->generate($mock, 10);
  
  # find previously-generated rows
  $rows= $table->generate($mock, { find => 1, rows => [{ id => 1 }] });

=head1 DESCRIPTION

This class is a L<Generator|Mock::Data::Generator> for a table in the schema.
It is created from a specification of columns, relationships, and keys.
It records all rows that it generates into the L<Mock::Data/generator_state>
in order to track the ongoing state of the relational data that is being built.

=head1 CONSTRUCTOR

=head2 new

The constructor can receive any of the attibutes, but also supports several shortcuts:

=over

=item C<< columns => [ \%column_spec, ... ] >>

If the columns are given as an arrayref, it provides a default for the L</column_order>.
It also applies a default C<idx> value on each column.

=item C<< columns => [ \%column_spec, \%relationship_spec, ... ] >>

You may combine column specifications with relationship specifications in the same array.
Relationships are identified by presence of C<cardinality> or one of the cardinality
shortcuts (C<1:N>, C<N:1>, C<1:1>, C<M:N>)

=item C<< columns => [ $name => \%column_spec, ... ] >>

If a value in the columns array is not a ref, then it is considered to be the name for
the following hashref.  The name will be added to C<%column_spec> automaticaly.

=item C<< columns => { $name => $generator } >>

If a value for a name is not a hashref, it is assumed to be the C<mock> attribute of the column.

=item C<< dbic_source => $DBIx_Class_ResultSource >>

You can provide an instance of L<DBIx::Class::ResultSource> and the L</columns>, L</keys>,
and L</relationships> will be built automatically from it.

=item C<< mock => { $name => $generator_spec, ... } >>

A specification of C<mock> will create implied columns of each name and assign its 'mock'
to the given generator.  This is useful in conjunction with C<dbic_source> which likely
provides everything except the C<mock> attributes.

=item C<< auto_mock => $which >>

If set to the value C<'not_null'>, every not-null column which does not have a mock value
defined will receive "something appropriate" according to its type and/or foreign key.
See L<Mock::Data::Relational/mock_generator_for_column>.

If set to the value C<'all'>, this will happen for nullable columns as well, resulting in
fully populated records.

=item C<< primary_key => $col_or_col_array >>

C<primary_key> is an alias for C<< keys->{primary}{cols} >>.

=back

=cut

sub new {
	my $class= shift;
	my $attrs= $class->coerce_attributes(@_);
	# Verify required attributes
	defined $attrs->{name} or croak("'name' is required");
	defined $attrs->{columns} && keys %{$attrs->{columns}}
		or croak "No columns specified.  (require 'columns' or 'mock' or 'dbic_source')";
	$attrs->{keys} ||= {};
	$attrs->{relationships} ||= {};
	# Process relationships to check for errors and calc additional attributes
	for my $rel (values %{ $attrs->{relationships} }) {
		$rel->{null} //= 0;
		if ($rel->{cols}) {
			for (@{ $rel->{cols} }) {
				my $c= $attrs->{columns}{$_}
					or croak "Relationship $rel->{name} refers to non-existent column $_";
				# nullable column indicates nullable relationship
				$rel->{null}= 1 if $c->{null};
			}
		}
		elsif ($rel->{rel}) {
			defined $attrs->{relationships}{$rel->{rel}}
				or croak "Relationship $rel->{name} refers to non-existent relationship $rel->{rel}";
		}
		else {
			croak "Relationship $rel->{name} must specify 'cols' or 'rel'";
		}
	}
	bless $attrs, $class;
}

=head1 ATTRIBUTES

=head2 name

Name of the table (or for DBIC, the name of the Result Source).  This module does not generate
any SQL, so this name does not need to match your actual database schema.  The name does get
used by relations to indicate which other table in the L</parent> they refer to, and in the
name of the generator added to the L<Mock::Data> instance.

=cut

sub name { $_[0]{name} }

=head2 columns

A hashref of C<< { $name => \%column_info, ... } >>.  Each item can hve the following
attributes:

=over

=item name

Name of the column.  This will be used as the hash key in the output rows.  Required, except
the constructor will automatically fill it in based on the hash key pointing to it.

=item type

The SQL data type for the data.  This should be a vendor-agnostic value for best results.
C<type> or C<mock> are required if the generator must generate a value for this column.

=item null

Boolean, whether the column may be null.  Defaults to false.

=item size

Either an integer (for things like varchar), or arrayref of integers (for numeric).

=item mock

A L<Mock::Data::Generator> (or specification for one).
C<type> or C<mock> are required if the generator must generate a value for this column.

=item idx

An integer specifying the sort-order of this column.

=back

For convenience, see L</coerce_column> or C</new> for various shorthand notations you can use
when constructing columns for a new instance.

=cut

sub columns { $_[0]{columns} }

=head2 column_order

An arrayref of the names of the columns in the order they should be presented.
If not specified, this is built from the C<< column_info->{idx} >> values, or lacking that,
alphabetical with primary key first.

=cut

sub column_order { $_[0]{column_order} ||= $_[0]->_build_column_order }

=head2 primary_key

Alias for C<< keys->{primary}{cols} >>

=head2 keys

A hashref of key names to info about the key:

  $key_name => {
    name => $key_name,
    cols => \@column_names,
    unique => $bool,
  }

There is usually a key named C<'primary'>, assembled from the columns marked "pk" or from the
constructor argument C<primary_key>.  Other unique or non-unique keys may be included.
As records are added, each key will be tracked so that duplicates can be detected, and so that
other tables referring by foreign key to these keys can know whether the row was already added
to this table or not.

=cut

sub primary_key { my $pk= shift->keys->{primary}; $pk? $pk->{cols} : undef }
sub _keys { $_[0]{keys} }
*keys= *_keys; # reduce pain of "Ambiguous call resolved as CORE::keys()"

=head2 relationships

A hashref of relation names from this table to another table.  Each relation is of the form:

  {
    name => $name,
  
  # direct relations:
  
    cardinality => ..., # '1:1', '1:N', 'N:1'
    cols        => \@self_column_names,
    peer        => $peer_table_name,
    peer_cols   => \@peer_column_names,
    is_fk       => $bool,
    null        => $bool,
  
  # or many-many relations:
  
    cardinality => 'N:N',
    rel         => $self_relation_to_peer,
    peer_rel    => $peer_relation_to_destination,
  }

When constructing rows, you may specify data for a relation and (like in DBIC) it will create
a related row.  If you don't specify data for the relation but it is a foreign key composed of
not-null columns, it will also create the related row (with mock data).

=cut

sub relationships { $_[0]{relationships} }

=head1 METHODS

=head2 coerce_attributes

  my $ctor_args= $class->coerce_attributes(...);

This is the implementation of the do-what-I-mean portion of L</new>.  It accepts any of the
shorthand notations described there and returns a hashref of official attributes.

=cut

sub coerce_attributes {
	my $self= shift;
	my $attrs= {
		@_ == 1 && ref $_[0] eq 'HASH'? %{$_[0]}
		: @_ == 1 && Scalar::Util::blessed($_[0]) && $_[0]->isa('DBIx::Class::ResultSource')? ( dbic_source => $_[0] )
		: @_
	};
	my $column_order= $attrs->{column_order};
	my $dbic_source= delete $attrs->{dbic_source};
	my %columns;
	my %rels;
	if ($attrs->{columns}) {
		# If a hashref, keys are column names and values are coerced to columns
		if (ref $attrs->{columns} eq 'HASH') {
			%columns= %{$attrs->{columns}};
			$_= $self->coerce_column($_) for values %columns;
			$columns{$_}{name}= $_ for keys %columns;
		}
		# If arrayref, read name first (if scalar) then read definition, which might be a
		# variety of things (understood by coerce_column)
		elsif (ref $attrs->{columns} eq 'ARRAY') {
			my $name= undef;
			my @order;
			for (@{ $attrs->{columns} }) {
				if (defined $name or ref $_ eq 'HASH') {
					my $f= $self->coerce_column_or_relationship($_);
					$name= $f->{name} unless defined $name;
					defined $name or croak "Encountered column with no name";
					if ($f->{cardinality}) { # actually a relationship
						$rels{$name}= $f;
					} else {
						$columns{$name}= $f;
						push @order, $name unless $column_order;
					}
					$name= undef;
				}
				elsif (!ref $_) {
					$name= $_;
				}
				else {
					croak "Expected column name or hashref in columns => [...]";
				}
			}
			$column_order ||= \@order;
		}
		else {
			croak "Expected arrayref or hashref for 'columns'";
		}
	}
	elsif ($dbic_source) {
		$attrs->{name} //= $dbic_source->name;
		for my $colname ($dbic_source->columns) {
			my $info= $dbic_source->column_info($colname);
			$columns{$colname}= $self->coerce_column({ %$info });
		}
		$column_order ||= [ $dbic_source->columns ];
	}

	if (my $mock= delete $attrs->{mock}) {
		if (ref $mock eq 'HASH') {
			for (keys %$mock) {
				$columns{$_}{mock}= $mock->{$_};
			}
		}
		elsif (ref $mock eq 'ARRAY') {
			my @order;
			for (my $i= 0; $i <= $#$mock; $i += 2) {
				$columns{ $mock->[$i] }{mock}= $mock->[$i+1];
				push @order, $mock->[$i] unless $column_order;
			}
			$column_order ||= \@order;
		}
		else {
			croak "Expected arrayref or hashref for 'mock'";
		}
	}

	# Make sure column spec contains its own name
	$columns{$_}{name} ||= $_ for keys %columns;

	if ($attrs->{relationships}) {
		for my $relname (keys %{ $attrs->{relationships} }) {
			$rels{$relname}= $self->coerce_relationship($attrs->{relationships}{$relname});
			$rels{$relname}{name}= $relname;
		}
	}
	if ($dbic_source) {
		for my $relname ($dbic_source->relationships) {
			my $info= $dbic_source->relationship_info($relname);
			$rels{$relname} ||= $self->coerce_relationship({ %$info });
		}
	}

	my %keys;
	if ($attrs->{keys}) {
		for my $keyname (keys %{ $attrs->{keys} }) {
			$keys{$keyname}= $self->coerce_key($attrs->{keys}{$keyname});
			$keys{$keyname}{name}= $keyname;
		}
	}
	if (defined (my $pk= delete $attrs->{primary_key})) {
		# can be a single column name, or array of names
		$keys{primary}= { cols => ( ref $pk? $pk : [ $pk ] ), unique => 1 };
	}
	if ($dbic_source) {
		for my $name ($dbic_source->unique_constraint_names) {
			$keys{$name} ||= {
				cols => [ $dbic_source->unique_constraint_columns($name) ],
				unique => 1
			};
		}
	}

	# If a primary key was given, make sure the columns are flagged as such
	# for correct default sorting.
	if (defined $keys{primary}) {
		my $i= 0;
		$columns{$_}{pk}= ++$i
			for @{ $keys{primary}{cols} };
	}

	# Apply column_order to the columns' idx attrs
	if ($column_order) {
		my $idx= 0;
		$columns{$_}{idx}= $idx++
			for @$column_order;
		$attrs->{column_order}= $column_order;
	}

	# Make sure the columns flagged as 'pk' are added to a key named 'primary'
	if (!defined $keys{primary}) {
		my @pk= map $_->{name}, sort {
				$a->{pk} <=> $b->{pk}
				or ($a->{idx}||0) <=> ($b->{idx}||0)
				or $a->{name} cmp $b->{name}
			}
			grep $_->{pk}, values %columns;
		$keys{primary}= { cols => \@pk, unique => 1 }
			if @pk;
	}

	# Make sure names of all keys are listed in the info
	$keys{$_}{name}= $_
		for keys %keys;

	# Convert "fk" found in the columns into foreign key relations.
	# "fk" is not part of the column spec, so remove it afterward.
	for my $col (grep $_->{fk}, values %columns) {
		my $fk= delete $col->{fk};
		my ($peer_table, $peer_column)= !ref $col->{fk}? split('.',$col->{fk}) : @{$col->{fk}};
		defined $peer_table && length $peer_table && defined $peer_column && length $peer_column
			or croak "Expected column fk to be an arrayref ['table'=>'column'] or scalar 'table.column'";
		my $has_unique_key= scalar grep {
				@{$_->{cols}} == 1
				and $_->{cols}[0] eq $col->{name}
				and $_->{unique}
			} values %keys;
		# The column and relation can have the same name.
		# If the user supplies a scalar for this name, it goes into the column.
		# If they supply a hashref for this name, it will find the relation and
		# create a related row.
		$rels{$col->{name}} ||= {
			name => $col->{name},
			cols => [ $col->{name} ],
			peer => $peer_table,
			peer_cols => [ $peer_column ],
			fk => 1,
			cardinality => $has_unique_key? '1:1' : 'N:1',
		};
	}
	if (my $auto_mock= delete $attrs->{auto_mock}) {
		my @cols= grep !exists $_->{mock}, values %columns;
		@cols= grep !$_->{null}, @cols
			if $auto_mock ne 'all';
		for my $col (@cols) {
			$col->{mock}= mock_generator_for_column($col, \%rels);
		}
	}

	$attrs->{columns}= \%columns if keys %columns;
	$attrs->{keys}= \%keys if keys %keys;
	$attrs->{relationships}= \%rels if keys %rels;
	$attrs->{column_order}= $column_order if defined $column_order;
	return $attrs;
}

sub _build_column_order {
	my $self= shift;
	return [
		map $_->{name},
		sort {
			# idx is authoritative
			defined $a->{idx} && defined $b->{idx} && $a->{idx} <=> $b->{idx}
			# else columns with a pk come first, in order of the value of pk
			or ($a->{pk}||0x7FFFFFFF) <=> ($b->{pk}||0x7FFFFFFF)
			# else sort by name
			or $a->{name} cmp $b->{name}
		} values %{ $self->columns }
	];
}

sub _key_search_seq {
	$_[0]{_key_search_seq} ||= $_[0]->_build__key_search_seq
}
sub _build__key_search_seq {
	return [
		sort {
			# Check primary key, then unique keys, then non-unique keys
			!($a->{name} eq 'primary') <=> !($b->{name} eq 'primary')
			or !$a->{unique} <=> !$b->{unique}
		}
		values %{ $_[0]->keys }
	]
}

sub coerce_column_or_relationship {
	my ($self, $spec)= @_;
	return { mock => $spec }
		unless ref $spec eq 'HASH';
	# actually a relationship?
	return $self->coerce_relationship($spec)
		if $spec->{cardinality} || $spec->{'1:N'} || $spec->{'N:1'}
			|| $spec->{'1:1'} || $spec->{'M:N'};
	return $self->coerce_column($spec);
}

sub coerce_column {
	my ($self, $spec)= @_;
	return { mock => $spec }
		unless ref $spec eq 'HASH';
	# Remap from DBIC names
	$spec->{type}= delete $spec->{data_type} if defined $spec->{data_type};
	$spec->{null}= 1 if delete $spec->{is_nullable};

	# If type has parenthesees and size not given, split it
	if ($spec->{type} && !defined $spec->{size} && $spec->{type} =~ /^([^(]+) \( (.+) \) $/x) {
		$spec->{type}= $1;
		my @size= split ',', $2;
		$spec->{size}= @size > 1? \@size : $size[0];
	}

	return $spec;
}

sub coerce_relationship {
	my ($self, $spec)= @_;
	ref $spec eq 'HASH'
		or croak "Relationship specification must be a hashref";
	my $mapping;
	if ($mapping= delete $spec->{'1:N'}) {
		%$spec= ( %$spec, cardinality => '1:N', _extract_cols_from_mapping($mapping) );
	} elsif ($mapping= delete $spec->{'1:1'}) {
		%$spec= ( %$spec, cardinality => '1:1', _extract_cols_from_mapping($mapping) );
	} elsif ($mapping= delete $spec->{'N:1'}) {
		%$spec= ( %$spec, cardinality => 'N:1', _extract_cols_from_mapping($mapping) );
	} elsif ($mapping= delete $spec->{'M:N'}) {
		$spec->{cardinality}= 'M:N';
		$spec->{rel}= $mapping->[0];
		$spec->{peer_rel}= $mapping->[1];
	}

	# TODO: handle DBIC translation

	# Verify required columns
	defined $spec->{cardinality} || croak "Relationship must specify 'cardinality'";
	defined $spec->{$_} || croak "Relationship must specify '$_'"
		for $spec->{cardinality} eq 'M:N'? qw( rel peer_rel ) : qw( peer cols peer_cols );
	return $spec;
}

# convert   { col => 'peer.pcol', ... }
# to        { cols => [ 'col' ], peer => 'peer', peer_cols => [ 'pcol ] }
sub _extract_cols_from_mapping {
	my $mapping= shift;
	my (@cols, @peer_cols, $peer);
	for my $col (keys %$mapping) {
		push @cols, $col;
		my @parts= split /[.]/, $mapping->{$col}, 2;
		if (@parts == 1) {
			push @peer_cols, $parts[0];
		} else {
			push @peer_cols, $parts[1];
			$peer= $parts[0] unless defined $peer;
			$peer eq $parts[0] or croak "Contradiction in foreign table: '$peer.' vs. '$parts[0].'";
		}
	}
	return (
		cols => \@cols,
		peer_cols => \@peer_cols,
		(defined $peer? ( peer => $peer ) : ())
	);
}

sub coerce_key {
	my ($self, $spec)= @_;
	return { cols => $spec } if ref $spec eq 'ARRAY';
	defined $spec->{cols} or croak "Key mst specify 'cols'";
	return $spec;
}

=head2 has_unique_key

  $key_info= $table->has_unique_key(@column_name_list);

Return the info hashref of a key in C<< $table->keys >> whose C<< ->{cols} >> are the same
(in any order) as the list of columns given and where C<< ->{unique} >> is true.
This only returns the first match.  It returns C<undef> if none of the unique keys match.

=cut

sub _unique_key_lookup { $_[0]{_unique_key_lookup} ||= $_[0]->_build__unique_key_lookup }
sub _build__unique_key_lookup {
	my $self= shift;
	return {
		map { join("\0", sort @{$_->{cols}}) => $_ }
			grep $_->{unique}, values %{ $self->keys }
	};
}
sub has_unique_key {
	my $self= shift;
	my @cols= @_ == 1 && ref $_[0] eq 'ARRAY'? @{ $_[0] } : @_;
	$self->_unique_key_lookup->{join("\0", sort @cols)};
}

=head2 generate

  $rows= $table->generate($mock, \%options);
            ...->generate($mock, \@rows);
            ...->generate($mock, $count);

This returns one or more records according to the schema of this table.  The records may be
newly generated or in some cases pulled from cache or a database.  The generated rows are
cached for later use and optionally written to a database.

This is a standard L<generate|Mock::Data::Generator/generate> method which can be given named
parameters in an initial hashref, or positional parameters, or both.

Available C<%options>:

=over

=item C<count>

The number of rows to generate.

=item C<rows>

An array of partial row hashrefs.  Each will have all its non-null missing fields filled in
and be added to the output, unless you ask for C<find>-mode and the record with a unique
key already existed, in which case the cached record gets returned.

=item C<find>

If the supplied rows match existing rows (according to keys) then return the existing rows.
If this is set to 1, return 1 row only if a unique key matches.  If this is set to '*', return
all rows if any key matches.

=item C<via_relationship>

  via_relationship => [ $table, $row, $rel_name ]

This describes a row of another table and a relationship that is being followed in order to
produce these rows.  The generated rows may receive additional default values from the original
row according to the columns of the relationship.

=item C<relationship_refs>

If true, the returned row hashrefs will include references to other row hashrefs for each
relationship that was processed.  (The default is to only return values for columns, with
related rows in other tables being referenced only logically by the foreign key values)

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

=cut

sub generate {
	my ($self, $mock)= (shift, shift);
	$mock->isa('Mock::Data') or croak "First argument must be Mock::Data";
	my %opts= ref $_[0] eq 'HASH'? %{shift()} : ();
	my @rows= ref $_[0] eq 'ARRAY'? @{$_[0]} : $opts{rows}? @{$opts{rows}} : ();
	my $count= defined $_[0] && !ref $_[0]? shift : $opts{count} // 1;
	croak "Unexpected parameter '$_[0]'" if @_;
	$opts{mock}= $mock;
	$opts{store}= _coerce_store($opts{store}, $mock);

	if ($count > @rows) {
		push @rows, undef for 1 .. ($count - @rows);
	}
	return $self->_generate(\%opts, \@rows);
	#unless ($opts{as_objects}) {
	#	ref $_ eq 'HASH' or ($_= { $_->get_columns })
	#		for @rows;
	#}
}

=head1 ROW GENERATION

In absence of relationships or constraints, this algorithm simply generates mock data for
each column where C<mock> was specified or which is non-nullable, and returns (and caches)
the rows.

If there are constraints, such as a unique index, the algorithm will possibly run a mock
generator multiple times for that column trying to get a distinct value.  It will give up
and throw an exception after a configurable number of tries.

If there are relationships, things get more complicated.  Related Records can be provided in
the rows using the name of the relationship, like so:

  {
    col1 => ...,
    col2 => ...,
    relationship1 => { col3 => ... },
    relationship2 => [
      { col4 => ..., col5 => ... },
      { col4 => ..., col5 => ... },
    ]
  }

In absence of related record, the relationship's own C<mock> attribute will be used to generate
related rows (or finalized rows).  But, the specific handling of these depends on the cardinality
of the relationship:

=over

=item C<1:1> Relationship, Local Key

This represents a record "continued into" another table.  This record will get created first,
then its PK used to create the related row.  If there is a seed record, or C<mock> defined for
the relationship, those will set additional fields to initialize the related row.

If creation fails, and a seed record was given, this dies, else it just ignores the error and
doesn't create the related row.

=item C<1:1> Relationship, Foreign Key

This record is a "continuation" of another row.  The related row must be found or created first,
then this row will inherit the foreign PK into the relationship's columns.

=item C<1:N> Relationship

This record may include one or more children.  This record gets created first, then its values
are used to initialize the related records.  If seed rows are provided, one related row is
created for each, else if the relationship C<mock> is defined, that method is called to
generate the seed rows, else a number 0..2 is chosen and that many records are created.

=item C<N:1> Relationship

This record is a child of another record.  The other record is found or created first, then
that key used to populate this record's columns.

=item C<M:N> Relationship, Hinge Table

If seed records are given, each one is found or created in the related table, then for each,
a record is added to the hinge table.

If no seed records are provided and no C<mock> is defined for the relationship, no related
rows get linked.

=item C<M:N> Relationship, Column Linkage

If seed records are given, or created by the relationship's C<mock> setting, they are found or
created in the related table.  Then the related columns are copied to this record.  If the
columns of the found records disagree about the value copied to this row's columns, it throws
an exception.

In absence of seed records or relationship mock generator, the normal column generators are
called and no related rows are created or checked for.

=back

=cut

sub _generate {
	my ($self, $params, $rows)= @_;
	my ($mock, $store, $via_relationship)= @{$params}{qw( mock store via_relationship )};
	my $cols= $self->columns;
	my @rels= values %{ $self->relationships };
	my $keys= $self->_key_search_seq;
	my @cols_with_mock= grep defined $_->{mock}, values %$cols;
	my @find_keys= !$params->{find}? ()
		: $params->{find} eq '*'? @{$self->_key_search_seq}
		: grep $_->{unique}, @{$self->_key_search_seq};
	my %gen_cache;

	my @ret;
	for my $row (@$rows) {
		# In 'find' mode, first check whether the $row has any keys that match existing rows
		if (@find_keys) {
			if (my @found= $store->find_rows($self, $row, @find_keys)) {
				push @ret, @found;
				next;
			}
		}

		# Iterate relationships, extracting their seed-values from the $row, and generating
		# any foreign key dependencies.
		my %related_rows;
		for my $rel (@rels) {
			my $rname= $rel->{name};
			my $peer= $mock->generators->{"Table::$rel->{peer}"}
				or croak "Table '$rel->{peer}' neded by relationship '$self->{name}.$rname' does not exist in \$mock->generators";
			# $row may contain values for the relatonship, but the relationship might also share
			# a name with a column.  If it could be a column, only treat it as relationship data
			# if the value is an arrayref or hashref and the column type is not json.
			my $rrows;
			$related_rows{$rname}= $rrows= delete $row->{$rname}
				if (ref $row->{$rname} eq 'ARRAY' || ref $row->{$rname} eq 'HASH')
					&& (!$self->columns->{$rname} || $self->columns->{$rname}{type} !~ /json/);
			# If a 1:1 or N:1 relationship is flagged as a foreign key,
			# and the user requested it be set, or it has a generator, or can't be null
			# the cols must come from the related row, which must be created if it doesn't exist.
			if (($rel->{cardinality} eq '1:1' || $rel->{cardinality} eq 'N:1')
				&& $rel->{fk}
				&& ($rrows || defined $rel->{mock} || !$rel->{null})
			) {
				if (!$rrows) {
					if ($rel->{mock}) {
						my $generator= $gen_cache{"r$rname"} //= coerce_generator($rel->{mock})->compile;
						$rrows= $generator->($mock, $params, 1);
					}
					$rrows //= {};
				}
				$related_rows{$rname}= $rrows= [ $rrows ] if ref $rrows eq 'HASH';
				@$rrows == 1 or croak "Must specify exactly one foreign row for relationship $rname";
				# Does the row have the foreign key in it?  Call generate if not.
				$peer->_generate($params, $rrows, [$self, $row, $rel])
					unless List::Util::all { defined $rrows->[0]{$_} } @{$rel->{peer_cols}};
				# Copy it from the remote row to current row
				_set_row_cols_from_peer($row, $rel, $rrows->[0]);
			}
		}

		# Check for unknown columns, now that relationships have been removed
		my @unknown= grep !defined $cols->{$_}, keys %$row;
		croak("Unknown fields in row: ".join(', ', @unknown))
			if @unknown;

		# Now apply mock values for every mockable column
		# TODO: make sure to generate unique values for unique keys
		for (grep !exists $row->{$_->{name}}, @cols_with_mock) {
			my $generator= $gen_cache{'c'.$_->{name}} //= coerce_generator($_->{mock})->compile;
			$row->{$_->{name}}= $generator->($mock, { table => $self, col => $_, row => $row });
		}
		# In multi-table mode, apply this record to the sequence of insertions
		if ($params->{multi_table}) {
			...
		}
		$store->create_row($self, $row);
		push @ret, $row;

		# Now create all related rows that depend on this record
		for my $rel (@rels) {
			my $rname= $rel->{name};
			my $peer= $mock->generators->{"Table::$rel->{peer}"};
			my $rrows= $related_rows{$rname};
			# avoid infinite recursion if this ->_generate was called by another _generate
			# on the other end of this relationship.
			next if $via_relationship && $peer == $via_relationship->[0]
				&& join("\0",sort @{$rel->{cols}}) eq join("\0",sort @{$via_relationship->[2]{peer_cols}});

			if ($rel->{cardinality} eq '1:1') {
				# If it is a foreign key, it has already been dealt with above.
				# Else, create one if there is a generator or specified related row
				if (!$rel->{fk} && ($rrows || defined $rel->{mock})) {
					unless ($rrows) {
						my $generator= $gen_cache{"r$rname"} //= coerce_generator($rel->{mock})->compile;
						$rrows= $generator->($mock, $params, 1);
					}
					$rrows= [ $rrows ] if ref $rrows eq 'HASH';
					@$rrows == 1 or croak "Must specify exactly one foreign row for relationship $rname";
					# copy key from this row to that row
					_set_peer_cols_from_row($rrows->[0], $rel, $row);
					$rrows= $peer->_generate({ %$params, find => 1, via_relationship => [$self, $row, $rel] }, $rrows);
					$row->{$rname}= $rrows->[0]
						unless $params->{multi_table};
				}
			}
			elsif ($rel->{cardinality} eq '1:N') {
				local $params->{find}= 0;
				local $params->{via_relationship}= [$self, $row, $rel];
				# 1:N are usually totally optional.  Use rows provided, else generator, else generate 0..2 rows.
				unless ($rrows) {
					if ($rel->{mock}) {
						my $generator= $gen_cache{"r$rname"} //= coerce_generator($rel->{mock})->compile;
						$rrows= $generator->($mock, $params, 1);
					} else {
						$rrows= [ ({}) x int rand 3 ];
					}
				}
				$rrows= [ $rrows ] if ref $rrows eq 'HASH';
				_set_peer_cols_from_row($_, $rel, $row) for @$rrows;
				$rrows= $peer->_generate($params, $rrows);
				
			}
			elsif ($rel->{cardinality} eq 'N:1') {
				# If it is a foreign key, it was dealt with above
				if (!$rel->{fk} && ($rrows || defined $rel->{mock})) {
					unless ($rrows) {
						my $generator= $gen_cache{"r$rname"} //= coerce_generator($rel->{mock})->compile;
						$rrows= $generator->($mock, $params, 1);
					}
					$rrows= [ $rrows ] if ref $rrows eq 'HASH';
					@$rrows == 1 or croak "Must specify exactly one foreign row for relationship $rname";
					# copy key from this row to that row
					_set_peer_cols_from_row($rrows->[0], $rel, $row);
					$rrows= $peer->_generate({ %$params, find => 1, via_relationship => [$self, $row, $rel] }, $rrows);
					$row->{$rname}= $rrows->[0]
						unless $params->{multi_table};
				}
			}
			elsif ($rel->{cardinality} eq 'M:N') {
				...
			}
			else {
				croak "Unknown cardinality '$rel->{cardinality}' for relationship $rel->{name}";
			}
		}
	}
	return \@ret;
}

sub _coerce_store {
	my ($store, $mock)= @_;
	# default to a cache inside Mock::Data instance
	return $mock->generator_state->{'Table::data'}
			//= Mock::Data::Plugin::Table::TableData->new()
		unless defined $store;
	return $store
		if blessed($store) && $store->isa('Mock::Data::Plugin::Table::TableData');
	return Mock::Data::Plugin::Table::TableData->new($store);
}

sub _set_peer_cols_from_row {
	my ($peer, $rel, $row)= @_;
	my @cols= @{$row}[@{$rel->{cols}}];
	unless (List::Util::all { defined } @cols) {
		my $link_msg= @{$rel->{cols}} == 1? $rel->{cols}[0]
			: '('.join(',', map "$_=".($row->{$_}//'NULL'), @{$rel->{cols}}).')';
		croak "Can't relate row.$rel->{name} => $rel->{peer} on NULL column: ".$link_msg;
	}
	@{$peer}[@{$rel->{peer_cols}}]= @cols;
}

sub _set_row_cols_from_peer {
	my ($row, $rel, $peer)= @_;
	my @pcols= @{$peer}[@{$rel->{peer_cols}}];
	unless (List::Util::all { defined } @pcols) {
		my $link_msg= @{$rel->{peer_cols}} == 1? $rel->{peer_cols}[0]
			: '('.join(',', map "$_=".($peer->{$_}//'NULL'), @{$rel->{peer_cols}}).')';
		croak "Can't relate row.$rel->{name} <= $rel->{peer} on NULL column: ".$link_msg;
	}
	@{$row}[@{$rel->{cols}}]= @pcols;
}

no Carp 'croak'; # clean up namespace
1;
