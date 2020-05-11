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

An arrayref of column names that compose the primary key.  This may be an empty arrayref for
tables with no primary key.  This will be automatically built from any columns you supplied
with a nonzero C<pk> attribute. (sorted by the pk attribute value)

=head2 relations

A hashref of relation names from this table to another table.  Each relation is of the form:

  {
    name => $name,
  
  # direct relations:
  
    cols        => \@self_column_names,
    peer        => $peer_table_name,
    peer_cols   => \@peer_column_names,
    is_fk       => \$bool
    cardinality => ...# '1:1', '1:N', 'N:1'
  
  # or many-many relations:
  
    rel         => $self_relation_to_peer,
    peer_rel    => $peer_relation_to_destination,
    cardinality => 'N:N'
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
has primary_key  => is => 'lazy';
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

sub BUILD {
	my ($self, $args)= @_;
	# Help user by checking for typos in arguments
	for (keys %$args) {
		croak "No such Table attribute ".$_
			unless $self->can($_);
	}
	# If a primary key was given, make sure the columns are flagged as such
	if (defined $args->{primary_key}) {
		my $i= 0;
		$self->columns->{$_}{pk}= ++$i
			for @{ $args->{primary_key} };
	}
	# If a column_order was given, make sure the column ->{idx} match
	if (defined $args->{column_order}) {
		my $i= 0;
		$self->columns->{$_}{idx}= $i++
			for @{ $args->{column_order} };
	}
	# Convert "fk" found in the columns into foreign key relations
	for my $col (grep $_->{fk}, values %{ $self->columns }) {
		# The column and relation can have the same name.
		# If the user supplies a scalar for this name, it goes into the column.
		# If they supply a hashref for this name, it will find the relation and
		# create a related row.
		$self->{relations}{$col->{name}}= {
			name => $col->{name},
			cols => [ $col->{name} ],
			peer => $col->{fk}[0],
			peer_cols => [ $col->{fk}[1] ],
		};
	}
}

sub _build_primary_key {
	my $self= shift;
	# No primary key was given.  Iterate the list of columns in column order
	# and collect any with 'pk' set on them.
	return [
		map $_->{name},
		sort { $a->{pk} <=> $b->{pk} or $a->{idx} <=> $b->{idx} }
		grep $_->{pk}, values %{ $self->columns }
	];
}

sub _build_column_order {
	my $self= shift;
	return [
		map $_->{name},
		sort {
			# idx is authoritative
			defined $a->{idx} && defined $b->{idx} && $a->{idx} <=> $b->{idx}
			# else columns with a pk come first, in order of the value of pk
			or (defined $b->{pk} <=> defined $a->{pk} or $a->{pk} <=> $b->{pk})
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
		$cols{$name}= { default => $cols{name} }
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

1;
