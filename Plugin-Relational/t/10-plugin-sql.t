#! /usr/bin/env perl
use Test2::V0;
use Mock::Data::Util qw( _escape_str );
use Mock::Data::Plugin::SQL;
use Mock::Data;
sub _flatten;

my $reps= $ENV{GENERATE_COUNT} || 5;

my $x_seq= 1;
my $y_seq= 1;
my @tests= (
	[ serial => [ 'X' ], validator(sub { $_ == $x_seq++ }) ],
	[ serial => [ 'Y' ], validator(sub { $_ == $y_seq++ }) ],
	[ integer => [], qr/^[0-9]+$/ ],
	[ numeric => [], qr/^[0-9]+$/ ],
	[ numeric => [5], qr/^[1-9][0-9]{0,4}$/ ],
	[ numeric => [[4,2]], qr/^[0-9]{0,2}\.[0-9]{2}$/ ],
);
my $mock= Mock::Data->new([qw( SQL )]);
for (@tests) {
	my ($generator, $args, $expected)= @$_;
	my $name= $generator . '(' . join(',', map _flatten, @$args) . ')';
	subtest $name => sub {
		for (1 .. $reps) {
			like( $mock->$generator(@$args), $expected );
		}
	};
}
sub _flatten {
	!ref $_? '"'._escape_str($_).'"'
	: ref $_ eq 'ARRAY'? '['.join(', ', map _flatten, @$_).']'
	: ref $_ eq 'HASH'? do {
		my $x= $_;
		'{'.join(', ', map "$_ => ".do{ &_flatten for $x->{$_}}, keys %$x).'}'
	}
	: "$_"
}

done_testing;
