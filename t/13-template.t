#! /usr/bin/env perl
use Test2::V0;
use Mock::Data::Util 'inflate_template';

my @tests= (
	[ 'a',                   'a' ],
	[ '{a}',                 'a1' ],
	[ '{a 2}',               'a2' ],
	[ '{a }',                'a1' ],
	[ '{b}',                 'b1' ],
	[ '{b x=5}',             'b5' ],
	[ '{b x==5}',            'b=5' ],
	[ '{a x=6}{b c x=4 d}',  'a1b4' ],
	# Invalid {} notation just results in no substitution performed
	[ '{',                   '{' ],
	[ 'x}',                  'x}' ],
	[ '{x',                  '{x' ],
	# Special template names that are just string escapes
	[ '{}',                  '' ],
	[ '{#20}',               ' ' ],
	[ '{#7B}',               '{' ],
	# nested templates
	[ '{a {#7B}}',           'a{' ],
	[ '{a x{#20}y}',         'ax y' ],
	[ '{b x{#3D}=4}',        'b1' ],
	[ '{b x={#3D}4}',        'b=4' ],
	[ '{a {b x={#3D}}}',     'ab=' ],
);
my $mockdata= MockRelData->new;
for (@tests) {
	my ($in, $out)= @$_;
	my $tname= !ref $in? $in : ref $in eq 'ARRAY'? join(' ', '[', @$in, ']') : '\\'.$$in;
	my $gen= inflate_template($in);
	my $val= ref $gen? $gen->generate($mockdata, {}) : $gen;
	is( $val, $out, $tname );
}

{
	package MockRelData;
	sub new { bless {}, shift }
	my %generators;
	BEGIN {
		%generators= (
			# return 'a' followed by the first non-named argument, defaulting to 1
			a => sub { 'a' . ($_[2] || 1) },
			# return 'b' followed by the argument named 'x', defaulting to 1
			b => sub { 'b' . ($_[1]{x} || 1) },
		);
	}
	sub generators { \%generators }
	sub call_generator {
		my $self= shift;
		my $name= shift;
		$generators{$name}->($self, @_);
	}
}

done_testing;
