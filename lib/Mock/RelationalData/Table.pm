package Mock::RelationalData::Table;
use Moo 2;
use Carp;

=head1 DESCRIPTION

This class represents a table in the schema.
It stores both the schema definition, and the rows that have been generated so far.

=head1 ATTRIBUTES

=head2 name

Name of the table (or for DBIC, the name of the Result Source).  This module does not generate
any SQL, so this is for your information only and does not need to match your database.

=head2 columns

A hashref of C<< { $column_name => \%column_info, ... } >>.  This may be passed to the
constructor in full, or using several shorthand notations:

=over

=item ArrayRef

This specifies the order of the columns if the C<column_order> attribute is not supplied.

  [ $column_name => \%column_info, ... ]

=item HashRef

This does not specify an order of the columns.  The C<column_order> attribute will get its
default value if not supplied.

  { $column_name => \%column_info, ... }

=item Scalar instead of column info

If the C<%column_info> portion is a scalar or scalar ref, it is assumed to be the C<fill> field
of the C<%column_info>.

  [ $column_name => $fill, ... ]
  # becomes
  { $column_name => { name => $column_name, fill => $fill } }

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

has name         => is => 'ro', required => 1;
has columns      => is => 'ro', required => 1, coerce => \&_coerce_columns;
has column_order => is => 'lazy';
sub primary_key  { my $pk= shift->keys->{primary}; $pk? $pk->{cols} : undef }
has keys         => is => 'ro', default => sub { +{} };
has relations    => is => 'ro', default => sub { +{} };

has rows         => is => 'rw', init_arg => undef, default => sub { [] };
has row_by_key   => is => 'rw', init_arg => undef, default => sub { +{} };

sub _pk_str {
	my ($self, $record)= @_;
	join "\0", grep(
		(defined $_ || croak "Record does not define all columns of primary key for table ".$self->name),
		@{$record}[@{ $self->primary_key }]
	);
}

our %_known_ctor_args= map +($_=>1), qw(
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
		$cols{$name}= { fill => $cols{$name} }
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

=head2 add_rows

=cut

sub add_rows {
	my $self= shift;
	my @rows= @_ == 1 && ref $_[0] eq 'ARRAY'? @{ $_[0] } : @_;
	...
}

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

1;
