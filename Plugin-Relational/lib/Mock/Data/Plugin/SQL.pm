package Mock::Data::Plugin::SQL;
use Exporter::Extensible -exporter_setup => 1;

# ABSTRACT: Collection of generators that produce data matching a SQL column type
# VERSION

=head1 SYNOPSIS

  $mock->integer(11);
  $mock->sequence($seq_name);
  $mock->numeric([9,2]);
  $mock->float({ bits => 32 });
  $mock->bit;
  $mock->varchar(16);
  $mock->char(16);
  $mock->text(256);
  $mock->date;
  $mock->datetime({ after => '1900-01-01', before => '1990-01-01' });
  $mock->blob(1000);
  $mock->uuid;
  $mock->json({ data => $data || {} });
  $mock->inet;
  $mock->cidr;
  $mock->macaddr;

This module defines generators that match the data type names used by various relational
databases.  

=cut

sub apply_mockdata_plugin {
	my ($class, $mockdata)= @_;
	$mockdata->load_plugin('Text')->add_generators(
		map +("SQL::$_" => $class->can($_)), qw(
			integer tinyint smallint bigint
			sequence serial smallserial bigserial
			numeric decimal
			float float4 real float8 double double_precision
			bit bool boolean
			varchar char nvarchar
			text tinytext mediumtext longtext ntext
			blob tinyblob mediumblob longblob
			varbinary binary
			date datetime timestamp
			uuid json inet cidr macaddr
		)
	);
}

=head1 GENERATORS

=head2 Numeric Generators

=head3 integer

  $int= $mock->integer($size_digits);
  $int= $mock->integer({ size => $digits, signed => $bool });
  $int= $mock->integer({ bits => $bits,   signed => $bool });
  $int= $mock

Returns a random integer up to C<$size> decimal digits or up to C<$bits>.
If C<$size> and C<$bits> are both specified, C<$size> wins.
If neither are specified, the default is C<< { bits => 31 } >>.
If C<signed> is undef, this generates non-negative integers, and the default
bits are reduced by one (7, 15, 31, 63).  If C<signed> is true, this generates
negative numbers.  If C<signed> is false, the number of default bits raises to
(8, 16, 32, 64).

The randomization chooses the length of the number (either bits or decimal digits)
separately from the value of the number.  This results in numbers tending toward
the middle string length, rather than an even distribution over the range of
values.

=head3 tinyint

Alias for C<< integer({ bits => 8 }) >>.

=head3 smallint

Alias for C<< integer({ bits => 16 }) >>.

=head3 bigint

Alias for C<< integer({ bits => 63 }) >>.

=cut

sub integer {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	my $size= shift // ($params? $params->{size} : undef);
	my $signed= $params? $params->{signed} : undef;
	if (defined $size) {
		my $digits= 1 + int rand($size > 1 && $signed? $size-2 : $size-1);
		my $val= 10**($digits-1) + int rand(9 * 10**($digits-1));
		return $signed && int rand 2? -$val : $val;
	} else {
		my $bits= ($params? $params->{bits} : undef) // 32;
		--$bits unless defined $signed && !$signed;
		$bits= int rand($bits+1);
		my $val= 2**($bits-1) + int rand(2 ** ($bits-1));
		return $signed && int rand 2? -$val : $val;
	}
}

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

  $int= $mock->sequence($seq_name);
  $int= $mock->sequence({ sequence_name => $seq_name });

Returns the next number in the named sequence, starting with 1.  The sequence name is required.
The state of the sequence is stored in C<< $mock->generator_state->{"SQL::sequence"}{$seq_name} >>.

=head3 serial

Alias for sequence

=head3 smallserial

Alias for sequence

=head3 bigserial

Alias for sequence

=cut

sub sequence {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	my $name= shift // ($params? $params->{sequence_name} : undef)
		// Carp::croak("sequence_name is required for sequence generator");
	return ++$mock->generator_state->{"SQL::sequence"}{$name};
}

*serial= *bigserial= *smallserial= *sequence;

=head3 numeric

  $str= $mock->numeric($size);
  $str= $mock->numeric([ $size, $scale ]);
  $str= $mock->numeric({ size => [ $size, $scale ] });

Note that this generator returns strings, to make sure to avoid floating imprecision.

=head3 decimal

Alias for C<numeric>.

=cut

sub numeric {
	my $mock= shift;
	my $params= ref $_ eq 'HASH'? shift : undef;
	my $size= shift // ($params? $params->{size} : undef) // 11;
	my $scale= 0;
	($size, $scale)= @$size if ref $size eq 'ARRAY';
	my $val= integer($mock, $size);
	main::note "size=$size scale=$scale val=$val";
	if ($scale) {
		$val= '0'x($scale+1 - length $val) . $val
			if length $val < $scale+1;
		substr($val, -$scale, 0)= '.';
	}
	return $val;
}

*decimal= *numeric;

=head3 float

  $str= $mock->float;
  $str= $mock->float($digits);
  $str= $mock->float({ size => $digits });
  $str= $mock->float({ bits => $n });

Generate a floating point number.  This uses a cheap randomization of choosing a number of
digits and then inserting a decimal point randomly.  This doesn't result in a very wide
variety of float, but at least they are easy to read.

The default size is 7, which approximates a 32-bit float.

=head3 real, float4

Aliases for C<< float({ size => 7 }) >>

=head3 float8, double, double_precision

Aliases for C<< float({ size => 15 }) >>

=cut

sub float {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	my $size= shift // ($params? ($params->{size} // int(($params->{bits} || 20) * .30103)): undef) // 7;
	my $val= int rand(10**$size);
	substr($val, int rand length $val, 0)= '.';
	return int rand 2? "-$val" : $val;
}

*real= *float4= *float;

sub double {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	float($mock, { size => 15, $params? %$params : () }, @_);
}

*float8= *double_precision= *double;

=head3 bit

Return a 0 or a 1

=head3 bool, boolean

Alias for C<bit>.  While postgres prefers C<'true'> and C<'false'>, it allows 0/1 and they are
more convenient to use in Perl.

=cut

sub bit {
	int rand 2;
}
*bool= *boolean= *bit;

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
	return $mock->call('Text::join', { source => $source_gen, max_len => $size, len => int rand $size });
}

*nvarchar= *varchar;

sub text {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	varchar($mock, { size => 256, ($params? %$params : ()) }, @_);
}

*ntext= *tinytext= *mediumtext= *longtext= *text;

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
	my @t= gmtime(shift);
	return sprintf "%04d-%02d-%02d %02d:%02d:%02d", $t[5]+1900, $t[4]+1, @t[3,2,1,0];
}
sub _iso8601_to_gmtime {
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
	my $before= $params && $params->{before}? _iso8601_to_gmtime($params->{before}) : (time - 86400);
	my $after=  $params && $params->{after}?  _iso8601_to_gmtime($params->{after})  : (time - int(10*365.25*86400));
	_epoch_to_iso8601($after + rand($before-$after)); 
}

sub date {
	substr(datetime(@_), 0, 10)
}

*timestamp= *datetime;

=head2 Binary Data Generators

=head3 blob

=head3 tinyblob, mediumblob, longblob, bytea, binary, varbinary

Aliases for C<blob>.  String lengths are not increased, because it would just slow things down.

=cut

sub blob {
	my $mock= shift;
	my $params= ref $_[0] eq 'HASH'? shift : undef;
	my $size= shift // ($params? $params->{size} : undef) // 256;
	my $data= '';
	my $n= int rand $size;
	for (0 .. ($n/2)) {
		$data .= pack 'v', rand 0x10000; 
	}
	$data .= pack 'c', rand 0x100
		if length $data < $n;
	return $data;
}

*tinyblob= *mediumblob= *longblob= *bytea= *binary= *varbinary= *blob;

=head2 Structured Data Generators

=head3 uuid

Return a "version 4" UUID composed of weak random bits from C<rand()>.

=cut

sub uuid {
	sprintf "%04x%04x-%04x-%04x-%04x-%04x%04x%04x",
		rand(1<<16), rand(1<<16), rand(1<<16),
		(4<<12)|rand(1<<12), (1<<15)|rand(1<<14),
		rand(1<<16), rand(1<<16), rand(1<<16)
}

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

*jsonb= *json;

=head3 inet

Return a random IP address within C<< 127.0.0.0/8 >>, excluding .0 and .255

=cut

sub inet {
	sprintf "127.%d.%d.%d", rand 256, rand 256, 1+rand 254;
}

=head3 cidr

Return a random CIDR starting with C<< 127. >> like C<< 127.0.42.0/24 >>

=cut

sub cidr {
	my $blank= 1 + int rand 23;
	my $val= (int rand(1<<(24 - $blank))) << $blank;
	sprintf '127.%d.%d.%d/%d', (unpack 'a', pack 'N', $val)[1,2,3], 32 - $blank;
}

=head3 macaddr

Return a random ethernet MAC in XX:XX:XX:XX:XX:XX format, taken from the Locally Administered
Address Ranges.

=cut

sub macaddr {
	sprintf '%02x:%02x:%02x:%02x:%02x:%02x',
		((rand 64)<<2) | 0x02, rand 256, rand 256,
		rand 256, rand 256, rand 256
}

1;
