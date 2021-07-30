#! /usr/bin/env perl
use Test2::V0;
use Mock::Data::Charset;

subtest charset_invlist => sub {
	my @tests= (
		[ 'A-Z', 0x7F,
			[ 65, 91 ]
		],
		[ 'A-Z', 0x200,
			[ 65, 91 ],
		],
		[ 'A-Za-z', 0x7F,
			[ 65, 91, 97, 123 ]
		],
		[ 'A-Za-z', 0x200,
			[ 65, 91, 97, 123 ]
		],
		[ '\w', 0x7F,
			[ 48, 58, 65, 91, 95, 96, 97, 123 ]
		],
	);
	for (@tests) {
		my ($notation, $max_codepoint, $expected)= @$_;
		my $invlist= Mock::Data::Charset::charset_invlist($notation, $max_codepoint);
		is( $invlist, $expected, "[$notation] ".($max_codepoint <= 127? 'ascii' : 'unicode') );
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

done_testing;
