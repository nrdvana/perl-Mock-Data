package Mock::Data::Plugin::Table::TableData;
use strict;
use warnings;
use Carp;

sub new {
	my $class= shift;
	# TODO: check for DBIx::Class::Schema which the user wants to write data to
	bless {}, $class;
}

sub read_from {
	$_[0]{read_from}
}

sub write_to {
	$_[0]{write_to}
}

sub cache {
	$_[0]{cache}
}

=head2 cached_rows

  @rows= $cache->cached_rows($table);

Return all cached rows for the given table.

=cut

sub cached_rows {
	my ($self, $table)= @_;
	return @{ $self->{cache}{$table->name}{''} //= [] };
}

=head2 cache_row

  $cache->cache_row($table, $row);

Add one row to the cache, for the given table.
If L</write_db> is set, this first writes it to the database, then caches the row object.

=cut

sub create_row {
	my ($self, $table, $row)= @_;
	my $table_cache= $self->{cache}{$table->name};
	my $cols= ref $row eq 'HASH'? $row : { $row->get_columns };
	for my $key (@{ $table->_key_search_seq }) {
		my $kv= join "\0", grep defined || next, @{$cols}{@{$key->{cols}}};
		my $index= $table_cache->{$key->{name}} //= {};
		if ($key->{unique}) {
			if (defined $index->{$kv}) {
				# whoops, conflict.  Need to un-do all the insertions so far in this loop
				for my $undo_key (@{ $table->_key_search_seq }) {
					last if $undo_key == $key;
					my $kv= join "\0", grep defined || next, @{$cols}{@{$undo_key->{cols}}};
					my $index= $table_cache->{$undo_key->{name}} //= {};
					if ($key->{unique}) { delete $index->{$kv} } else { pop @{ $index->{$kv} } }
				}
				croak "Duplicate row for key $key->{name}: ".join(', ', @{$cols}{@{$key->{cols}}});
			}
			$index->{$kv}= $row;
		} else {
			push @{$index->{$kv}}, $row;
		}
	}
	push @{$table_cache->{''}}, $row;
}

=head2 find_or_create

=cut

sub find_or_create {
	my ($self, $table, $row)= @_;
	return $self->find_rows($table, $cols, grep $_->{unique}, @{ $table->_key_search_seq })
		// $self->create_row($table, $cols);
}

=head2 find_rows

  @rows= $cache->find_rows($table, \%columns)
  @rows= $cache->find_rows($table, \%columns, $key)

Find any rows that were indexed by any key, using the first key whose required columns
are defined in C<%columns>.  Keys are checked in order of Primary, unique, non-unique.

To use a specific key only, pass that as an additional parameter.

=cut

sub find_rows {
	my ($self, $table, $cols, @keys)= @_;
	for my $key (@keys? @keys : @{ $table->_key_search_seq }) {
		my $kv= join "\0", grep defined || next, @{$cols}{@{$key->{cols}}};
		my $rows= $self->{cache}{$table->name}{$key->{name}}{$kv};
		return !$rows? () : ref $rows eq 'ARRAY'? @$rows : ( $rows );
	}
	return;
}

1;
