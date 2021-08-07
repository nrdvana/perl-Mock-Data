#! /usr/bin/env perl
use Test2::V0;
use Mock::Data::Generator::Charset;
use Mock::Data;
use Data::Dumper;
sub charset { Mock::Data::Generator::Charset->new(@_) }

subtest parse_charset => sub {
	my @tests= (
		[ 'A',
			{ codepoints => [65] },
		],
		[ '^ABC',
			{ codepoints => [65,66,67], negate => T() },
		],
		[ 'A-Z',
			{ codepoint_ranges => [65,90], },
		],
		[ 'A-Za-z',
			{ codepoint_ranges => [65,90, 97,122], },
		],
		[ '-Za-z',
			{ codepoints => [ord('-'),90], codepoint_ranges => [97,122] },
		],
		[ 'A-Za-',
			{ codepoints => [ord('-'),97], codepoint_ranges => [65,90] },
		],
		[ '\w',
			{ classes => ['word'] },
		],
		[ '\N{SPACE}',
			{ codepoints => [32] },
		],
		[ '\N{SPACE}-0',
			{ codepoint_ranges => [32,48] },
		],
		[ '\p{digit}',
			{ classes => ['digit'] },
		],
		[ '[:digit:]',
			{ classes => ['digit'] },
		],
		[ '\\0',
			{ codepoints => [0] },
		],
		[ '\\o{0}',
			{ codepoints => [0] },
		],
		[ '\\x20',
			{ codepoints => [0x20] },
		],
		[ '\\x{450}',
			{ codepoints => [0x450] },
		],
		#[ '\cESC',
		#	{ chars => [27], ranges => [], classes => [], negate => F() },
		#]
	);
	for (@tests) {
		my ($spec, $expected)= @$_;
		is( Mock::Data::Generator::Charset::parse($spec), $expected, '['.$spec.']' );
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
		my $invlist= charset(notation => $notation, max_codepoint => $max_codepoint)->member_invlist;
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
		my $members= Mock::Data::Generator::Charset::_expand_invlist_members($invlist);
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
		my $index= Mock::Data::Generator::Charset::_create_invlist_index($invlist);
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
		my $charset= charset(member_invlist => $invlist);
		my $members= $charset->members;
		is( $members->[$ofs], $expected, "$name - expect $members->[$ofs]" );
		is( $charset->get_member($ofs), $expected, $name );
	}
};

subtest charset_string => sub {
	my $mock= Mock::Data->new();
	my $str= charset('A-Z')->generate($mock);
	like( $str, qr/^[A-Z]+$/, '[A-Z], default size' );
	$str= charset('a-z')->generate($mock, { size => 20 });
	like( $str, qr/^[a-z]{20}$/, '[a-z] size=20' );
	$str= charset('0-9')->generate($mock, { min_size => 30, max_size => 31 });
	like( $str, qr/^[0-9]{30,31}$/, '[0-9] size=[30..31]' );
};

subtest parse_regex => sub {
	my @tests= (
		[ qr/abc/, { expr => [ 'abc' ] } ],
		[ qr/a*/,  { expr => ['a'], repeat => [0,] } ],
		[ qr/a+b/, { expr => [ { expr => ['a'], repeat => [1,] }, 'b' ] } ],
		[ qr/a(ab)*b/, { expr => [ 'a', { expr => ['ab'], repeat => [0,] }, 'b' ] } ],
		[ qr/a[abc]d/, { expr => [ 'a', hash{ item chars => [ord 'a', ord 'b', ord 'c']; etc; }, 'd' ] } ],
		[ qr/^a/,   { expr => [ { at => { start => 1    } },    'a' ] } ],
		[ qr/^a/m,  { expr => [ { at => { start => 'LF' } },    'a' ] } ],
		[ qr/a$/,   { expr => [ 'a', { at => { end => 'FinalLF' } } ] } ],
		[ qr/a$/m,  { expr => [ 'a', { at => { end => 'LF'      } } ] } ],
		[ qr/a\Z/m, { expr => [ 'a', { at => { end => 1         } } ] } ],
		[ qr/\w/m, { classes => ['word'] } ],
		[ qr/\w+\d+/, { expr => [{ classes => ['word'], repeat => [1,] },{ classes => ['digit'], repeat => [1,] }] } ],
		[ qr/(abc\w+)?/, { expr => [ 'abc', { classes => ['word'], repeat => [1,] } ], repeat => [0,1] } ],
	);
	for (@tests) {
		my ($regex, $expected)= @$_;
		my $parse= Mock::Data::Charset::parse_regex($regex);
		is( $parse, $expected, "regex $regex" )
			or diag Data::Dumper::Dumper($parse);
	}
};

subtest regex_generator => sub {
	my @tests= (
		qr/^abc$/,
		qr/abc/,
		qr/a+b/,
		qr/a(ab)*b/,
		qr/a[abc]d/,
		#qr/a(ab$)*/,
		#qr/a(ab$)*/m,
	);
	my $mock= Mock::Data->new();
	for my $regex (@tests) {
		subtest "regex $regex" => sub {
			my $generator= Mock::Data::Charset::build_generator_for_regex($regex);
			for (1..10) {
				my $str= $generator->($mock);
				like( $str, $regex, "Str=$str" );
			}
		};
	}
};

done_testing;
