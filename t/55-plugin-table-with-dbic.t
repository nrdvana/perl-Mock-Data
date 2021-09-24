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
PRAGMA foreign_keys = ON;

CREATE TABLE artist(
  artistid    INTEGER PRIMARY KEY, 
  artistname  TEXT
);

CREATE TABLE track(
  trackid     INTEGER,
  trackname   TEXT, 
  trackartist INTEGER,
  FOREIGN KEY(trackartist) REFERENCES artist(artistid)
);
END
	my $mock= Mock::Data->new(['Table']);
	$mock->declare_tables($db);
	like( $mock->generators, { Artist => D(), Track => D() }, 'Have Artist and Track generators' );
	my $data= $mock->Artist(10);
	like( $data, [ ({})x10 ], '10 rows' );
	my $rows= $db->resultset('Artist')->populate($data);
	like( $rows, [ (D())x10 ], '10 row objects' );
};

done_testing;
