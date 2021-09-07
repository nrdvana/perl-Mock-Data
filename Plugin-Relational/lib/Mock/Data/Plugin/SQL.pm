package Mock::Data::Plugin::SQL;
use Mock::Data::Plugin -exporter_setup => 1;
use Mock::Data::Plugin::Net qw( cidr macaddr ), 'ipv4', { -as => 'inet' };
use Mock::Data::Plugin::Number qw( integer decimal float sequence uuid byte );
use Mock::Data::Plugin::Text join => { -as => 'text_join' };
my @generator_methods= qw(
	integer tinyint smallint bigint
	sequence serial smallserial bigserial
	numeric decimal
	float float4 real float8 double double_precision
	bit bool boolean
	varchar char nvarchar
	text tinytext mediumtext longtext ntext
	blob tinyblob mediumblob longblob bytea
	varbinary binary
	date datetime timestamp
	json jsonb
	uuid inet cidr macaddr
);
export(@generator_methods);

# ABSTRACT: Collection of generators that produce data matching a SQL column type
# VERSION

=head1 SYNOPSIS

  my $mock= Mock::Data->new(['SQL']);
  $mock->integer(11);
  $mock->sequence($seq_name);
  $mock->numeric([9,2]);
  $mock->float({ bits => 32 });
  $mock->bit;
  $mock->boolean;
  $mock->varchar(16);
  $mock->char(16);
  $mock->text(256);
  $mock->blob(1000);
  $mock->varbinary(32);
  $mock->datetime({ after => '1900-01-01', before => '1990-01-01' });
  $mock->date;
  $mock->uuid;
  $mock->json({ data => $data || {} });
  $mock->inet;
  $mock->cidr;
  $mock->macaddr;

This module defines generators that match the data type names used by various relational
databases.  

The output patterns are likely to change in future versions, but will always be valid for
inserting into a column of that type.

=cut

sub apply_mockdata_plugin {
	my ($class, $mock)= @_;
	$mock->load_plugin('Text')->add_generators(
		map +("SQL::$_" => $class->can($_)), @generator_methods
	);
}

=head1 GENERATORS

=head2 Numeric Generators

=head3 integer

See L<Mock::Data::Plugin::Number/integer>

=head3 tinyint

Alias for C<< integer({ bits => 8 }) >>.

=head3 smallint

Alias for C<< integer({ bits => 16 }) >>.

=head3 bigint

Alias for C<< integer({ bits => 63 }) >>.

=cut

sub tinyint {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	integer($mock, { $params? %$params : (), bits => 8 }, @_);
}

sub smallint {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	integer($mock, { $params? %$params : (), bits => 16 }, @_);
}

sub bigint {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	integer($mock, { $params? %$params : (), bits => 64 }, @_);
}

=head3 sequence

See L<Mock::Data::Plugin::Number/sequence>

=head3 serial

Alias for sequence

=head3 smallserial

Alias for sequence

=head3 bigserial

Alias for sequence

=cut

BEGIN { *bigserial= *smallserial= *serial= *sequence; }

=head3 decimal

See L<Mock::Data::Plugin::Numeric/decimal>

=head3 numeric

Alias for C<decimal>.

=cut

BEGIN { *numeric= *decimal; }

=head3 float

See L<Mock::Data::Plugin::Numeric/float>

=head3 real, float4

Aliases for C<< float({ size => 7 }) >>

=head3 float8, double, double_precision

Aliases for C<< float({ size => 15 }) >>

=cut

BEGIN { *real= *float4= *float; }

sub double {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	float($mock, { bits => 53, $params? %$params : () }, @_);
}

BEGIN { *float8= *double_precision= *double; }

=head3 bit

Return a 0 or a 1

=head3 bool, boolean

Alias for C<bit>.  While postgres prefers C<'true'> and C<'false'>, it allows 0/1 and they are
more convenient to use in Perl.

=cut

sub bit {
	int rand 2;
}
BEGIN { *bool= *boolean= *bit; }

=head2 Text Generators

=head3 varchar

  $str= $mock->varchar($size);
  $str= $mock->varchar({ size => $size });

Generate a string of random length, from 1 to C<$size> characters.  If C<$size> is not given, it
defaults to 16.  If there is a generator named C<'word'>, this will pull strings from that up to
the random chosen length.

=head3 text

Same as varchar, but the default size is 256.

=head3 tinytext, mediumtext, longtext, ntext

Aliases for C<text>, and don't generate larger data because that would just slow things down.

=cut

sub varchar {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	my $size= shift // ($params? $params->{size} : undef) // 16;
	my $source= ($params? $params->{source} : undef) // 'word';
	my $source_gen= ref $source? $source : $mock->generators->{$source}
		// Carp::croak("No generator '$source' available");
	return text_join($mock, { source => $source_gen, max_len => $size, len => int rand $size });
}

BEGIN { *nvarchar= *varchar; }

sub text {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	varchar($mock, { size => 256, ($params? %$params : ()) }, @_);
}

BEGIN { *ntext= *tinytext= *mediumtext= *longtext= *text; }

=head3 char

  $str= $mock->char($size);
  $str= $mock->char({ size => $size });

Same as varchar, but the default size is 1, and the string will be padded with whitespace
up to C<$size>.

=cut

sub char {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	my $size= @_? shift : ($params? $params->{size} : undef) // 1;
	my $str= varchar($mock, ($params? $params : ()), $size);
	$str .= ' 'x($size - length $str) if length $str < $size;
	return $str;
}

=head2 Date Generators

=head3 datetime

  $datestr= $mock->datetime();
  $datestr= $mock->datetime({ before => $date, after => $date });

Returns a random date from a date range, defaulting to the past 10 years.
The input and output date strings must all be in ISO-8601 format, or an object that stringifies
to that format.  The output does not have the 'T' in the middle or 'Z' at the end, for widest
compatibility with being able to insert into databases.

=head3 date

Like C<datetime>, but only the C<'YYYY-MM-DD'> portion.

=head3 timestamp

Alias for C<datetime>.

=cut

sub _epoch_to_iso8601 {
	my @t= localtime(shift);
	return sprintf "%04d-%02d-%02d %02d:%02d:%02d", $t[5]+1900, $t[4]+1, @t[3,2,1,0];
}
sub _iso8601_to_epoch {
	my $str= shift;
	$str =~ /^
		(\d{4}) - (\d{2}) - (\d{2})
		(?: [T ] (\d{2}) : (\d{2})  # maybe time
			(?: :(\d{2})            # maybe seconds
				(?: \. \d+ )?       # ignore milliseconds
			)?
			(?: Z | [-+ ][:\d]+ )?  # ignore timezone or Z
		)?
	/x or Carp::croak("Invalid date '$str'.  Expecting format YYYY-MM-DD[ HH:MM:SS[.SSS][TZ]]");
	require POSIX;
	return POSIX::mktime($6||0, $5||0, $4||0, $3, $2-1, $1-1900);
}

sub datetime {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	my $before= $params && $params->{before}? _iso8601_to_epoch($params->{before}) : (time - 86400);
	my $after=  $params && $params->{after}?  _iso8601_to_epoch($params->{after})  : (time - int(10*365.25*86400));
	_epoch_to_iso8601($after + int rand($before-$after)); 
}

sub date {
	substr(datetime(@_), 0, 10)
}

BEGIN { *timestamp= *datetime; }

=head2 Binary Data Generators

=head3 blob

=head3 tinyblob, mediumblob, longblob, bytea, binary, varbinary

Aliases for C<blob>.  None of these change the default string length, because longer strings
of data would just slow things down.

=cut

sub blob {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	my $size= shift // ($params? $params->{size} : undef) // 256;
	byte($mock, $size);
}

BEGIN { *tinyblob= *mediumblob= *longblob= *bytea= *binary= *varbinary= *blob; }

=head2 Structured Data Generators

=head3 uuid

See L<Mock::Data::Plugin::Numeric/uuid>

=head3 json, jsonb

Return '{}'.  This is just the minimal valid value that makes it most likely that you can
perform operations on the column without type errors.

=cut

our $json;
sub _json_encoder {
	$json //= do {
		local $@;
		my $mod= eval { require JSON::MaybeXS; 'JSON::MaybeXS' }
			  || eval { require JSON; 'JSON' }
			  || eval { require JSON::XS; 'JSON::XS' }
			or Carp::croak("No JSON module found.  This must be installed for the SQL::json generator.");
		$mod->new->canonical->ascii
	};
}

sub json {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	my $data= shift // ($params? $params->{data} : undef);
	return defined $data? _json_encoder->encode($data) : '{}';
}

BEGIN { *jsonb= *json; }

=head3 inet

See L<Mock::Data::Plugin::Net/ipv4>

=head3 cidr

See L<Mock::Data::Plugin::Net/cidr>

=head3 macaddr

See L<Mock::Data::Plugin::Net/macaddr>

=cut

1;
