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
		[ '\\012',
			{ codepoints => [10] },
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
		is( Mock::Data::Generator::Charset->parse($spec), $expected, '['.$spec.']' );
	}
};

subtest merge_invlists => sub {
	my @tests= (
		[ [ 0, 1, 2, 3 ], [ 1, 2, 3, 4 ] ]
			=> [ 0, 4 ],
		[ [ 0, 50 ], [ 50 ] ]
			=> [ 0 ],
		[ [ 0, 50 ], [ 0, 50 ] ]
			=> [ 0, 50 ],
		[ [ 0, 50 ], [ 0, 51 ] ]
			=> [ 0, 51 ],
		[ [ 0, 50 ], [ 1, 50 ] ]
			=> [ 0, 50 ],
		[ [ 0, 50 ], [ 1, 49 ] ]
			=> [ 0, 50 ],
		[ [ 0, 50 ], [ 1, 51 ] ]
			=> [ 0, 51 ],
		[ [ 10, 20 ], [ 0, 10, 20 ] ],
			=> [ 0 ],
	);
	while (my ($input, $output)= splice(@tests, 0, 2)) {
		is( Mock::Data::Generator::Charset::Util::merge_invlists($input), $output );
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
		[ '^[:digit:]', 0x7F,
			[ 0,0x30, 0x3A,0x80 ],
		],
		[ '[:alpha:]\P{digit}', 0x7F,
			[ 0,0x30, 0x3A,0x80 ],
		],
		[ '\p{alpha}\P{alpha}', undef,
			[ 0 ],
		],
		[ '^\n', undef,
			[ 0,10, 11 ]
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
		my $members= Mock::Data::Generator::Charset::Util::expand_invlist($invlist);
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
		my $index= Mock::Data::Generator::Charset::Util::create_invlist_index($invlist);
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
		is( ord $members->[$ofs], $expected, "$name - expect $members->[$ofs]" );
		is( $charset->get_member_codepoint($ofs), $expected, $name );
	}
};

subtest get_member_find_member => sub {
	my $charset= charset('[:punct:]');
	for (my $i= 0; $i < $charset->count; $i++) {
		my $ch= $charset->get_member($i);
		is( $charset->find_member($ch), $i, "found $ch at $i" );
	}
	is( [ $charset->find_member("\n") ], [ undef, 0 ], '\n would insert at position 0' );
	is( [ $charset->find_member("A") ], [ undef, 17 ], '[ would insert at position 26' );
};

subtest lazy_attributes => sub {
	my $charset= charset('[:alpha:]\P{digit}');
	diag Data::Dumper::Dumper($charset->member_invlist);
	ok( !$charset->find_member('0'), '"0" not in the set of alpha and non-digit' );
	is( scalar $charset->find_member('a'), 87, 'member "a" found at 87' );
	ok( defined $charset->{member_invlist} && defined $charset->{_invlist_index}, 'used invlist' );
	ok( !defined $charset->{members}, 'did not use members[]' );
	
	$charset= charset(classes => ['alpha','^digit']);
	ok( !$charset->find_member('0'), '"0" not in the set of alpha and non-digit' );
	is( scalar $charset->find_member('a'), 87, 'member "a" found at 87' );
	ok( defined $charset->{member_invlist} && defined $charset->{_invlist_index}, 'used invlist' );
	ok( !defined $charset->{members}, 'did not use members[]' );

	$charset= charset(notation => '[:alpha:]\P{digit}', max_codepoint => 127);
	is( $#{$charset->members}, 117, '117 ascii non-digit chars' );
	is( $charset->get_member(87), 'a', 'found a at expected offset' );
	ok( defined $charset->{members}, 'used members[]' );
	ok( !defined $charset->{_invlist_index}, 'did not use invlist index' );
};

subtest charset_string => sub {
	my $mock= Mock::Data->new();
	my $str= charset('A-Z')->generate($mock);
	like( $str, qr/^[A-Z]+$/, '[A-Z], default size' );
	$str= charset('a-z')->generate($mock, { len => 20 });
	like( $str, qr/^[a-z]{20}$/, '[a-z] size=20' );
	$str= charset('0-9')->generate($mock, { min_len => 30, max_len => 31 });
	like( $str, qr/^[0-9]{30,31}$/, '[0-9] size=[30..31]' );
	$str= charset('0-9')->generate($mock, 1);
	like( $str, qr/^[0-9]$/, '[0-9] size=1' );
	$str= charset('0-9')->generate($mock, { max_codepoint => ord '0' }, 50);
	like( $str, qr/^0+$/, '[0-9] max_codepoint => /0+/' );
};

done_testing;
