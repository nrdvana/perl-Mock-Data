#! /usr/bin/env perl
use Test2::V0;
use Mock::RelationalData::Gen 'compile_generator', 'compile_template';

my @tests= (
	[ 'a',                   'a' ],
	[ '{a}',                 'a1' ],
	[ '{a 2}',               'a2' ],
	[ '{a }',                'a1' ],
	[ '{b}',                 'b1' ],
	[ '{b x=5}',             'b5' ],
	[ '{a x=6}{b c x=4 d}',  'a1b4' ],
	# Invalid {} notation just results in no substitution performed
	[ '{',                   '{' ],
	[ 'x}',                  'x}' ],
	[ '{x',                  '{x' ],
	[ '{}',                  '' ],
	[ '{ }',                 '{ }' ],
	[ '{ a}',                '{ a}' ],
	# arrayref notation randomly selects from an element of the array,
	# and each element is recrsively processed
	[ ['a'],                 'a' ],
	[ ['{a}'],               'a1' ],
	[ ['{a'],                '{a' ],
	# scalar ref is passed through unchanged
	[ \'{a}',                '{a}' ],
);
my $reldata= MockRelData->new;
for (@tests) {
	my ($in, $out)= @$_;
	my $tname= !ref $in? $in : ref $in eq 'ARRAY'? join(' ', '[', @$in, ']') : '\\'.$$in;
	my $gen= compile_generator($in);
	is( $gen->($reldata, {}), $out, $tname );
}

{
	package MockRelData;
	sub new { bless {}, shift }
	sub generators {
		return {
			# return 'a' followed by the first non-named argument, defaulting to 1
			a => sub { 'a' . ($_[2] || 1) },
			# return 'b' followed by the argument named 'x', defaulting to 1
			b => sub { 'b' . ($_[1]{x} || 1) },
		}
	}
}

done_testing;
