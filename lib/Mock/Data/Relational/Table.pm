package Mock::Data::Relational::Table;
use strict;
use warnings;
use Carp;
use parent 'Mock::Data::Generator';

=head1 DESCRIPTION

This class is a L<Mock::Data::Generator|Generator> for a table in the schema.
It is created from a specification of columns, relationships, and keys.
It records all rows that it generates into the L<Mock::Data/generator_state>.

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
    is_fk       => \$bool,
  
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

sub _key_of_row {
	my ($self, $record, $key_cols)= @_;
	join "\0", grep(
		(defined $_ || return undef),
		@{$record}{@$key_cols}
	);
}

=head1 METHODS

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

=item C<< primary_key => $col_or_col_array >>

C<primary_key> is an alias for C<< keys->{primary}{cols} >>.

=back

=cut

sub new {
	my $class= shift;
	my $args= $class->coerce_constructor_args(@_);
	defined $args->{name} or croak "'name' is required";
	bless $args, $class;
}

sub coerce_constructor_args {
	my $self= shift;
	my $args= { @_ == 1 && ref $_[0] eq 'HASH'? %{$_[0]} : @_ };
	my $column_order= $args->{column_order};
	my $dbic_source= delete $args->{dbic_source};
	my %columns;
	my %rels;
	if ($args->{columns}) {
		# If a hashref, keys are column names and values are coerced to columns
		if (ref $args->{columns} eq 'HASH') {
			%columns= %{$args->{columns}};
			$_= $self->coerce_column($_) for values %columns;
			$columns{$_}{name}= $_ for keys %columns;
		}
		# If arrayref, read name first (if scalar) then read definition, which might be a
		# variety of things (understood by coerce_column)
		elsif (ref $args->{columns} eq 'ARRAY') {
			my $name= undef;
			my @order;
			for (@{ $args->{columns} }) {
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
					croak "Expected column name or hashref";
				}
			}
			$column_order ||= \@order;
		}
		else {
			croak "Expected arrayref or hashref for 'columns'";
		}
	}
	elsif ($dbic_source) {
		for my $colname ($dbic_source->columns) {
			my $info= $dbic_source->column_info($colname);
			$columns{$colname}= $self->coerce_column({ %$info });
		}
		$column_order ||= [ $dbic_source->columns ];
	}
	elsif (!$args->{mock}) {
		croak "No columns specified.  (require 'columns' or 'mock' or 'dbic_source')"
	}

	if (my $mock= delete $args->{mock}) {
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

	if ($args->{relationships}) {
		for my $relname (keys %{ $args->{relationships} }) {
			$rels{$relname}= $self->coerce_relationship($args->{relationships}{$relname});
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
	if ($args->{keys}) {
		for my $keyname (keys %{ $args->{keys} }) {
			$keys{$keyname}= $self->coerce_key($args->{keys}{$keyname});
			$keys{$keyname}{name}= $keyname;
		}
	}
	if (defined (my $pk= delete $args->{primary_key})) {
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
		$args->{column_order}= $column_order;
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
			is_fk => 1,
			cardinality => $has_unique_key? '1:1' : 'N:1',
		};
	}

	$args->{columns}= \%columns;
	$args->{keys}= \%keys;
	$args->{relationships}= \%rels;
	$args->{column_order}= $column_order if defined $column_order;
	return $args;
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
	$spec->{null}= delete $spec->{is_nullable} if defined $spec->{is_nullable};

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
			$peer eq $parts[0] or croak "Contradiction in foreign table: '$peer' vs. '$parts[0]'";
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

sub populate {
	my $self= shift;
	my $tname= $self->name;
	my $rows= @_ == 1 && ref $_[0] eq 'ARRAY'? $_[0] : [ @_ ];
	# If given tabular notation, with list of columns on first row, convert to normal hashrefs
	# Some day this could be reversed, storing everything as the more efficient arrayref notation,
	# but that is more effort and harder to debug.
	if (ref $rows->[0] eq 'ARRAY') {
		my $cols= shift @$rows;
		for my $row (@$rows) {
			$row= $self->add_row(map +( $_ => $row->{$_} ), @$cols);
		}
	}
	else {
		for my $row (@$rows) {
			$row= $self->add_row(%$row);
		}
	}
	return $rows; # array has been modified to contain the expanded row hashrefs
}

sub find_or_create {
	my ($self, $row)= @_;
	# Search for any key which this row has the columns for.  Check unique keys first.
	for (sort { !$a->{unique} <=> !$b->{unique} } values %{ $self->keys }) {
		# kv is undef if any required column is missing
		if (defined (my $kv= $self->_key_of_row($row, $_->{cols}))) {
			my $existing= $self->_row_by_key->{$_->{name}}{$kv};
			return $existing if defined $existing;
		}
	}
	# Not found.  Create a new one.
	return $self->add_row($row);
}

#has _mock_cache => is => 'lazy';
sub _build__mock_cache {
	my $self= shift;
	my %mockers;
	for my $col (values %{ $self->columns }) {
		if (exists $col->{mock}) {
			$mockers{$col->{name}}= $self->parent->compile_generator($col->{mock});
		}
		elsif (!$col->{is_nullable} && !defined $col->{default_value}) {
			my $tname= $self->name;
			$mockers{$col->{name}}= $self->parent->get_mock_generator_for_col($col)
				# Set the generator to an error message
				|| sub { croak "Must specify value for column $col->{name} of table $tname; no mocker specified" };
		}
		# Else no need for a mocker- the column will default to NULL or DB will give it a default
	}
	\%mockers;
}

=head2 rows_of

  $row_array= $table->rows_of($mockdata);
  $row_set=   $table->rows_of($mockdata, $key_name);

This fetches the current set of defined rows from the generator_state of C<$mockdata>.
If given a key name, it returns the set of rows for that key.  Else it returns the arrayref
of all rows.

=cut

sub rows_of {
	my ($self, $mockdata, $key_name)= @_;
	my $st= $mockdata->generator_state->{__PACKAGE__ . '.' . $self->{name}} ||= {};
	return $st->{row_by_key}{$key_name} ||= {}
		if defined $key_name;
	return $st->{rows} ||= [];
}

sub add_row {
	my $self= shift;
	my $row= { @_ == 1 && ref $_[0] eq 'HASH'? %{$_[0]} : @_ };
	my $cols= $self->columns;
	my $rels= $self->relations;
	my @key_list= sort { !$a->{unique} <=> !$b->{unique} } values %{ $self->keys };
	my $mock_cache= $self->_mock_cache;
	my %related_rows;

	# The user could supply a mix of column or relations.  Verify that the columns
	# all exist, and if a relation, find/create the related data and then link back
	# the foreign key column.
	for (keys %$row) {
		# Special handling if user provides data for a relation
		if ($rels->{$_} && (!$cols->{$_} || ref $row->{$_} eq 'HASH' || ref $row->{$_} eq 'ARRAY')) {
			$related_rows{$_}= delete $row->{$_};
		}
		elsif (!$cols->{$_}) {
			croak "No such column or relation '$_' for table ".$self->name;
		}
	}

	# Now apply mock values for every mockable column
	for (keys %$mock_cache) {
		# TODO: exclude foreign keys when $related_rows given for that foreign key
		$row->{$_}= $mock_cache->{$_}->($self, $cols->{$_})
			unless exists $row->{$_};
	}

	relation_loop: for my $rel (values %$rels) {
		if (my $rval= $related_rows{$rel->{name}}) {
			my @peer_rows= ref $rval eq 'ARRAY'? @$rval : ( $rval );
			# If the relation uses columns from this table which are defined in this row,
			# include this row's values into the data that is being find-or-created.
			for (0 .. $#{$rel->{cols}}) {
				my $col= $rel->{cols}[$_];
				my $peer_col= $rel->{peer_cols}[$_];
				for (@peer_rows) {
					$_->{$peer_col}= $row->{$col} unless exists $_->{$peer_col};
				}
			}
			# find-or-create the records in the related table.
			my $peer_table= $self->parent->tables->{$rel->{peer}}
				or croak "No such table '$rel->{peer}' referenced by relation '$rel->{name}' of table ".$self->name;
			$peer_table->find_or_create(\@peer_rows);
			# If this record did not define one or more of the values for the relation,
			# pull them from the related record.
			for (0 .. $#{$rel->{cols}}) {
				my $col= $rel->{cols}[$_];
				my $peer_col= $rel->{peer_cols}[$_];
				$row->{$col}= $peer_rows[0]{$peer_col}
					unless exists $row->{$col};
			}
		}
		elsif ($rel->{is_fk}) {
			my %fk;
			for (0..$#{ $rel->{cols} }) {
				my $col= $rel->{cols}[$_];
				my $peer_col= $rel->{peer_cols}[$_];
				# Can't exist unless the FK is fully not-null
				next relation_loop unless defined $row->{$col};
				$fk{$peer_col}= $row->{$col};
			}
			my $peer_table= $self->parent->tables->{$rel->{peer}}
				or croak "No such table '$rel->{peer}' referenced by relation '$rel->{name}' of table ".$self->name;
			$peer_table->find_or_create(\%fk);
		}
	}
	
	# For each key, add the row to that key's index.  If the key is unique, verify
	# that the row isn't a duplicate.
	my %kvs;
	for my $key (@key_list) {
		if (defined (my $kv= $self->_key_of_row($row, $key->{cols}))) {
			if ($key->{unique} && $self->_row_by_key->{$key->{name}}{$kv}) {
				# whoops, duplicate.  Remove any references added to this row so far in this loop
				delete $self->_row_by_key->{$_}{$kvs{$_}} for keys %kvs;
				$kv =~ s/\0/,/g;
				croak "Attempt to add_row with duplicate key '$key->{name}': ($kv)";
			}
			$self->_row_by_key->{$key->{name}}{$kv}= $row;
			$kvs{$key->{name}}= $kv;
		}
	}

	# Row is official now
	push @{ $self->rows }, $row;
	return $row;
}

1;
