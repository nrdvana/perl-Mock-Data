#! /usr/bin/env perl
use Test2::V0;
use Mock::Data::Charset;
use Data::Dumper;

subtest parse_charset => sub {
	my @tests= (
		[ 'A',
			{ chars => [65], ranges => [], classes => [], negate => F() },
		],
		[ '^ABC',
			{ chars => [65,66,67], ranges => [], classes => [], negate => T() },
		],
		[ 'A-Z',
			{ chars => [], ranges => [[65,90]], classes => [], negate => F() },
		],
		[ 'A-Za-z',
			{ chars => [], ranges => [[65,90],[97,122]], classes => [], negate => F() },
		],
		[ '-Za-z',
			{ chars => [ord('-'),90], ranges => [[97,122]], classes => [], negate => F() },
		],
		[ 'A-Za-',
			{ chars => [ord('-'),97], ranges => [[65,90]], classes => [], negate => F() },
		],
		[ '\w',
			{ chars => [], ranges => [], classes => ['word'], negate => F() },
		],
		[ '\N{SPACE}',
			{ chars => [32], ranges => [], classes => [], negate => F() },
		],
		[ '\N{SPACE}-0',
			{ chars => [], ranges => [[32,48]], classes => [], negate => F() },
		],
		[ '\p{digit}',
			{ chars => [], ranges => [], classes => ['digit'], negate => F() },
		],
		[ '[:digit:]',
			{ chars => [], ranges => [], classes => ['digit'], negate => F() },
		],
		[ '\\0',
			{ chars => [0], ranges => [], classes => [], negate => F() },
		],
		[ '\\o{0}',
			{ chars => [0], ranges => [], classes => [], negate => F() },
		],
		[ '\\x20',
			{ chars => [0x20], ranges => [], classes => [], negate => F() },
		],
		[ '\\x{450}',
			{ chars => [0x450], ranges => [], classes => [], negate => F() },
		],
		#[ '\cESC',
		#	{ chars => [27], ranges => [], classes => [], negate => F() },
		#]
	);
	for (@tests) {
		my ($spec, $expected)= @$_;
		is( Mock::Data::Charset::parse_charset($spec), $expected, '['.$spec.']' );
	}
};

subtest charset_invlist => sub {
	my @tests= (
		[ 'A-Z', 0x7F,
			[ 65,91 ]
		],
		[ 'A-Z', undef,
			[ 65,91 ],
		],
		[ 'A-Za-z', 0x7F,
			[ 65,91, 97,123 ]
		],
		[ 'A-Za-z', undef,
			[ 65,91, 97,123 ]
		],
		[ '\w', 0x7F,
			[ 48,58, 65,91, 95,96, 97,123 ]
		],
		[ '\w', 0x200,
			[ 48,58, 65,91, 95,96, 97,123, 0x100,0x201 ],
		],
		[ '\s', 0x7F,
			[ 9,14, 32,33 ],
		],
		[ '\s', undef,
			[ 9,14, 32,33, 133,134, 160,161, 5760,5761, 8192,8203, 8232,8234, 8239,8240, 8287,8288, 12288,12289 ],
		],
		[ '\p{Block: Katakana}', undef,
			[ 0x30A0, 0x3100 ],
		],
	);
	for (@tests) {
		my ($notation, $max_codepoint, $expected)= @$_;
		my $invlist= Mock::Data::Charset::charset_invlist($notation, $max_codepoint);
		is( $invlist, $expected, "[$notation] ".($max_codepoint && $max_codepoint <= 127? 'ascii' : 'unicode') );
	}
};

subtest expand_invlist_members => sub {
	my @tests= (
		[ 'digits', [48,58], [48,49,50,51,52,53,54,55,56,57] ],
		[ 'one char', [0,1], [0] ],
		[ 'two chars', [5,6,7,8], [5,7] ],
		[ 'three chars', [3,4,5,6,7,8], [3,5,7] ],
		[ 'unbounded', [0x10FFFE], [0x10FFFE,0x10FFFF] ],
		[ '2+unbounded', [5,6,7,8,0x10FFFE], [5,7,0x10FFFE,0x10FFFF] ],
	);
	for (@tests) {
		my ($name, $invlist, $expected)= @$_;
		my $members= Mock::Data::Charset::expand_invlist_members($invlist);
		is( $members, $expected, $name );
	}
};

subtest create_invlist_index => sub {
	my @tests= (
		[ 'digits', [48,58], [10] ],
		[ 'A-Za-z', [65,91,97,123], [26,52] ],
		[ 'three chars', [3,4,5,6,7,8], [1,2,3] ],
		[ 'unbounded', [3,4,5,6,7], [1,2,2+0x10FFFF-6] ],
	);
	for (@tests) {
		my ($name, $invlist, $expected)= @$_;
		my $index= Mock::Data::Charset::create_invlist_index($invlist);
		is( $index, $expected, $name );
	}
};

subtest get_invlist_element => sub {
	my @tests= (
		[ 'digit 5', [48,58], 5, 53 ],
		[ 'hex 11', [48,58,65,71], 11, 66 ],
		[ 'hex  0', [48,58,65,71],  0, 48 ],
		[ 'hex 15', [48,58,65,71], 15, 70 ],
		[ 'hex  9', [48,58,65,71],  9, 57 ],
		[ 'hex 10', [48,58,65,71], 10, 65 ],
	);
	for (@tests) {
		my ($name, $invlist, $ofs, $expected)= @$_;
		my $index= Mock::Data::Charset::create_invlist_index($invlist);
		my $members= Mock::Data::Charset::expand_invlist_members($invlist);
		is( $members->[$ofs], $expected, "$name - expect $members->[$ofs]" );
		is( Mock::Data::Charset::get_invlist_element($ofs, $invlist, $index), $expected, $name );
	}
};

subtest charset_string => sub {
	require Mock::Data;
	my $mock= Mock::Data->new(['Charset']);
	my $str= $mock->charset_string('A-Z');
	like( $str, qr/^[A-Z]+$/, '[A-Z], default size' );
	$str= $mock->charset_string({ size => 20 }, 'a-z');
	like( $str, qr/^[a-z]{20}$/, '[a-z] size=20' );
	$str= $mock->charset_string({ min_size => 30, max_size => 31 }, '0-9');
	like( $str, qr/^[0-9]{30,31}$/, '[0-9] size=[30..31]' );
};

subtest parse_regex => sub {
	my @tests= (
		[ qr/abc/, { expr => [ 'abc' ] } ],
		[ qr/a*/,  { expr => ['a'], min_size => 0 } ],
		[ qr/a+b/, { expr => [ { expr => ['a'], min_size => 1 }, 'b' ] } ],
		[ qr/a(ab)*b/, { expr => [ 'a', { expr => ['ab'], min_size => 0 }, 'b' ] } ],
		[ qr/a[abc]d/, { expr => [ 'a', hash{ chars => [ord 'a', ord 'b', ord 'c']; etc; }, 'd' ] } ],
	);
	for (@tests) {
		my ($regex, $expected)= @$_;
		my $parse= Mock::Data::Charset::parse_regex($regex);
		is( $parse, $expected, "regex $regex" ) or diag Data::Dumper::Dumper($parse);
	}
};

done_testing;
