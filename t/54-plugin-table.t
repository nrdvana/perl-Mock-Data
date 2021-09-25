#! /usr/bin/env perl
use Test2::V0;
use Mock::Data;

my $mock= Mock::Data->new([qw/ Table /]);
$mock->declare_schema(
	Test1 => [
		id    => { auto_increment => 1 },
		value => { type => 'numeric' },
	],
);

is(
	$mock->call('table','Test1',1),
	[ hash { etc; } ],
	'call generator for Test1 directly'
);

done_testing;
