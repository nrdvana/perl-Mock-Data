#! /usr/bin/env perl
use Test2::V0;
use Mock::Data;
use FindBin;
use lib "$FindBin::RealBin/lib";

eval {
	require LiveDBTestUtil;
	require DBD::SQLite;
} or do {
	note $@;
	plan skip_all => 'This test requires DBIx::Class and sqlite and Schema::Loader';
};

subtest simple_schema => sub {
	my $db= LiveDBTestUtil::new_sqlite_schema(<<END);
CREATE TABLE artist(
  artistid    INTEGER PRIMARY KEY, 
  artistname  TEXT
);
CREATE TABLE track(
  trackid     INTEGER,
  trackname   TEXT, 
  trackartist INTEGER NOT NULL,
  FOREIGN KEY(trackartist) REFERENCES artist(artistid)
);
END
	my $mock= Mock::Data->new(['Table']);
	$mock->declare_tables($db);
	like( $mock->generators, { Artist => D(), Track => D() }, 'Have Artist and Track generators' );
	my $data= $mock->Artist(10);
	like( $data, [ ({})x10 ], '10 Artist rows' );
	my $rows= $db->resultset('Artist')->populate($data);
	like( $rows, [ (D())x10 ], '10 Artist row objects inserted' );
	$data= $mock->Track(10);
	like( $data, [ ({ trackartist => {} })x10 ], '10 Track rows with related artist' );
	use DDP; note &np([$mock->generator_state]);
	$rows= $db->resultset('Artist')->populate($data);
	like( $rows, [ (D())x10 ], '10 Track row objects inserted' );
};

done_testing;
