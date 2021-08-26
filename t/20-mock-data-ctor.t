#! /usr/bin/env perl
use Test2::V0;
use Mock::Data;

my @tests= (
	{
		name => 'Plain set of generators',
		args => [ generators => { a => [42] } ],
		check => object {
			call generators => { a => [42] };
		}
	},
	{
		name => 'Relative package name plugin',
		args => [['MyPlugin']],
		check => object {
			call generators => { a => [40] };
		}
	},
	{
		name => 'Abs package name plugin',
		args => [ with => ['My::Plugin2'] ],
		check => object {
			call generators => { 'My::Plugin2::a' => [60], a => [60] };
		}
	},
	{
		name => 'Plugin and literal generator override',
		args => [ with => ['My::Plugin2'], generators => { a => [22], b => [55] } ],
		check => object {
			call generators => { 'My::Plugin2::a' => [60], a => [22], b => [55] };
		}
	},
	{
		name => 'Plugin merge',
		args => [[qw/ MyPlugin My::Plugin2 /]],
		check => object {
			call generators => { 'My::Plugin2::a' => [60], a => [40,60] };
		}
	},
	{
		name => 'Plugin no mrge in reverse order',
		args => [[qw/ My::Plugin2 MyPlugin /]],
		check => object {
			call generators => { 'My::Plugin2::a' => [60], a => [40] };
		}
	}
);

for (@tests) {
	my $mockdata= Mock::Data->new(@{ $_->{args} });
	is( $mockdata, $_->{check}, $_->{name} );
}

{
	package Mock::Data::Plugin::MyPlugin;
	sub apply_mockdata_plugin {
		my ($class, $mockdata)= @_;
		$mockdata->add_generators(
			a => [ 40 ],
		);
	}
}
{
	package MyPlugin;
	sub apply_mockdata_plugin {
		my ($class, $mockdata)= @_;
		$mockdata->add_generators(
			a => [ 50 ],
		);
	}
}
{
	package My::Plugin2;
	sub apply_mockdata_plugin {
		my ($class, $mockdata)= @_;
		$mockdata->merge_generators(
			'My::Plugin2::a' => [ 60 ],
		);
	}
}

done_testing;
