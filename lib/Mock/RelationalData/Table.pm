package Mock::RelationalData::Table;
use Moo 2;
use Carp;

=head1 DESCRIPTION

This class represents a table in the schema.
It stores both the schema definition, and the rows that have been generated so far.

=head1 ATTRIBUTES

=head2 parent

A reference to the L<Mock::RelationalData> which this table belongs to.  This is a weak
reference.

=head2 name

Name of the table (or for DBIC, the name of the Result Source).  This module does not generate
any SQL, so this name does not need to match your actual database schema.  The name does get
used by relations to indicate which other table in the L</parent> they refer to, and it shows
up in the output when you export the aggregate data of the L</parent>.

=head2 columns

A hashref of C<< { $column_name => \%column_info, ... } >>.  This may be passed to the
constructor in full, or using several shorthand notations:

=over

=item ArrayRef

This specifies the order of the columns if the C<column_order> attribute is not supplied.

  [ $column_name => \%column_info, ... ]

=item HashRef

This specifies the column info without an ordering.  Use in conjunction with the C<column_order>
attribute if you care about the column order.

  { $column_name => \%column_info, ... }

=item Scalar instead of %column_info

If the C<%column_info> portion is a scalar, scalar ref, or coderef, it is assumed to be the
C<mock> field of the C<%column_info>.

  [ $column_name => $mock_tpl, ... ]
  # becomes
  { $column_name => { name => $column_name, mock => $mock_tpl } }

=back

=head2 column_order

An arrayref of the names of the columns in the order they should be presented.
If not specified, this is built from the C<< column_info->{idx} >> values, or lacking that,
alphabetical with primary key first.

=head2 primary_key

Alias for C<< keys->{primary} >>.

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

=head2 relations

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

=head2 rows

This is the current arrayref of all data rows for this table.  You should not set these
directly; use the L</add_rows> method.  Rows are stored as arrayrefs in L</column_order>.

=head2 row_by_key

This is an index of the row data added so far.  It is a hashref of key names to row keys to
row arrayrefs.

=cut

has parent       => is => 'ro', required => 1, weak_ref => 1;
has name         => is => 'ro', required => 1;
has columns      => is => 'ro', required => 1, coerce => \&_coerce_columns;
has column_order => is => 'lazy';
sub primary_key  { my $pk= shift->keys->{primary}; $pk? $pk->{cols} : undef }
has keys         => is => 'ro', default => sub { +{} };
has relations    => is => 'ro', default => sub { +{} };

has rows         => is => 'rw', init_arg => undef, default => sub { [] };
has _row_by_key  => is => 'rw', init_arg => undef, default => sub { +{} };

sub _key_of_row {
	my ($self, $record, $key_cols)= @_;
	join "\0", grep(
		(defined $_ || return undef),
		@{$record}{@$key_cols}
	);
}

our %_known_ctor_args= map +($_=>1), qw(
	parent
	name
	columns
	column_order
	keys
	primary_key
	relations
);
sub BUILD {
	my ($self, $args)= @_;
	# Help user by checking for typos in arguments
	croak "No such Table attribute ".$_ for grep !$_known_ctor_args{$_}, keys %$args;
	
	# If a primary key was given, make sure the columns are flagged as such
	# for correct default sorting.
	if (defined $args->{primary_key}) {
		my $i= 0;
		my @pk= !ref $args->{primary_key}? ($args->{primary_key}) : @{$args->{primary_key}};
		$self->columns->{$_}{pk}= ++$i
			for @pk;
		$self->keys->{primary}= { cols => \@pk, unique => 1 };
	}
	
	# If a column_order was given, it takes priority over any ->{idx} found on columns.
	if (defined $args->{column_order}) {
		my $i= 0;
		$self->columns->{$_}{idx}= $i++
			for @{ $args->{column_order} };
	}
	
	# Make sure the columns flagged as 'pk' are added to a key named 'primary'
	if (!defined $self->keys->{primary}) {
		my @pk= map $_->{name}, sort { $a->{pk} <=> $b->{pk} or $a->{idx} <=> $b->{idx} }
			grep $_->{pk}, values %{ $self->columns };
		$self->keys->{primary}= { cols => \@pk, unique => 1 }
			if @pk;
	}
	
	# Make sure names of all keys are listed in the info
	$self->keys->{$_}{name}= $_
		for keys %{ $self->keys };
	
	# Convert "fk" found in the columns into foreign key relations
	for my $col (grep $_->{fk}, values %{ $self->columns }) {
		my ($peer_table, $peer_column)= !ref $col->{fk}? split('.',$col->{fk}) : @{$col->{fk}};
		defined $peer_table && length $peer_table && defined $peer_column && length $peer_column
			or croak "Expected column fk to be an arrayref ['table'=>'column'] or scalar 'table.column'";
		# The column and relation can have the same name.
		# If the user supplies a scalar for this name, it goes into the column.
		# If they supply a hashref for this name, it will find the relation and
		# create a related row.
		$self->{relations}{$col->{name}}= {
			name => $col->{name},
			cols => [ $col->{name} ],
			peer => $peer_table,
			peer_cols => [ $peer_column ],
			is_fk => 1,
			cardinality => $self->has_unique_key($col->{name})? '1:1' : 'N:1',
		};
	}
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

sub _coerce_columns {
	my $x= shift;
	my %cols= ref $x eq 'ARRAY'? @$x
		: ref $x eq 'HASH'? %$x
		: croak "Expected an arrayref or hashref for 'columns'";
	for my $name (keys %cols) {
		# If the value is not a hashref, then it is the default generator
		$cols{$name}= { mock => $cols{$name} }
			if ref $cols{$name} ne 'HASH';
		$cols{$name}{name}= $name;
	}
	# If given as an array, set the idx field on each column in the order that the
	# names were given in the list.
	if (ref $x eq 'ARRAY') {
		my ($i, $col_idx)= (0,0);
		$cols{$_}{idx}= $col_idx++ for grep ++$i & 1, @$x;
	}
	
	return \%cols;
}

=head1 METHODS

=head2 has_unique_key

  $key_info= $table->has_unique_key(@column_name_list);

Return the info hashref of a key in C<< $table->keys >> whose C<< ->{cols} >> are the same
(in any order) as the list of columns given and where C<< ->{unique} >> is true.
This only returns the first match.  It returns C<undef> if none of the unique keys match.

=cut

has _unique_key_lookup  => is => 'lazy';
sub _build__unique_key_lookup {
	my $self= shift;
	return {
		map { join("\0", sort @{$_->{cols}}) => $_ }
			grep $_->{unique}, values %{ $self->keys }
	};
}
sub has_unique_key {
	my $table= shift;
	my @cols= @_ == 1 && ref $_[0] eq 'ARRAY'? @{ $_[0] } : @_;
	$table->_unique_key_lookup->{join("\0", sort @cols)};
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
		if (defined (my $kv= _key_of_row($row, $_->{cols}))) {
			my $existing= $self->_row_by_key->{$kv};
			return $existing if defined $existing;
		}
	}
	# Not found.  Create a new one.
	return $self->add_row($row);
}

has _mock_cache => is => 'lazy';
sub _build__mock_cache {
	my $self= shift;
	my %mockers;
	for my $col (values %{ $self->columns }) {
		if (exists $col->{mock}) {
			$mockers{$col->{name}}= $self->parent->get_mock_generator($col->{mock});
		}
		elsif (!$col->{is_nullable} && !defined $col->{default_value}) {
			my $tname= $self->name;
			local $@;
			$mockers{$col->{name}}= eval { $self->parent->get_mock_generator_for_col($col) }
				|| sub { "Must specify value for column $col->{name} of table $tname; no mocker specified" };
		}
		# Else no need for a mocker- the column will default to NULL or DB will give it a default
	}
	\%mockers;
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
