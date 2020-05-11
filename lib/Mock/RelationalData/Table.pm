package Mock::RelationalData::Table;
use Moo 2;
use Carp;

has name         => is => 'rw', required => 1;
has columns      => is => 'rw', required => 1, coerce => \&_coerce_columns;
has column_order => is => 'rw', lazy => 1, builder => 1, predicate => 1;
has primary_key  => is => 'rw', lazy => 1, builder => 1;
has relations    => is => 'rw', default => sub { +{} };

has rows         => is => 'rw', default => sub { [] };
has row_by_key   => is => 'rw', default => sub { +{} };

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
