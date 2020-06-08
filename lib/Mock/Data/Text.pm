package Mock::Data::Text;
use strict;
use warnings;

=head1 SYNOPSIS

  my $mockdata= Mock::Data->new(['Text']);
  $mockdata->wordchar($size)    # string of \w+
  $mockdata->words($size)       # string of (\w+ )+
  $mockdata->lorem_ipsum($size) # classic boilerplate

=head1 DESCRIPTION

This plugin for L<Mock::Data> generates simple text patterns.

=cut

sub apply_plugin {
	my ($class, $mockdata)= @_;
	$mockdata->merge_generators(
		map { "${class}::$_" => $class->can($_) }
		qw( wordchar words lorem_ipsum );
	);
}

=head2 wordchar

  wordchar($reldata, {})              # length 16 of \w+
  wordchar($reldata, {size => $size}) # length $size of \w+
  wordchar($reldata, {}, $size)       # length $size of \w+

Returns a string of characters from the set of C<< /\w+/ >>.

The size defaults to 16, but can be overridden with a named or unnamed argument.

=cut

my @char_set= split //, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
sub wordchar :Export {
	my ($reldata, $args, $size)= @_;
	$size= $args->{size} if !defined $size && $args && defined $args->{size};
	my $ret= '';
	$ret .= $char_set[rand scalar @char_set] for 1..$size;
	return $ret;
}

sub alpha :Export {
	
}

=head2 words

Returns a sequence of wordchar separated by space.

=cut

my $words_picker= weighted_tpl_set(
	4 => '{alpha 2}',
	9 => '{alpha 3}',
	5 => '{alpha 4}',
	5 => '{alpha 5}',
	5 => '{alpha 6}',
	2 => '{alpha 7}',
	2 => '{alpha 8}',
	2 => '{alpha 9}',
);
sub words :Export {
	my ($reldata, $args, $size)= @_;
	$size= $args->{size} if !defined $size && $args && defined $args->{size};
	my $ret= $words_picker->evaluate(@_);
	$ret .= ' ' . $words_picker->evaluate(@_)
		while length $ret < $size;
	return substr($ret, 0, $size);
}

=head2 lorem_ipsum

=head2 lorem

  lorem_ipsum($reldata, {size => $size})
  lorem_ipsum($reldata, {}, $size})

Repetitions of the classic 1500's Lorem Ipsum text up to length C<size>

The default size is one iteration of the string.

=cut

my $lorem_ipsum_classic=
 "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor "
."incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis "
."nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.  "
."Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu "
."fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in "
."culpa qui officia deserunt mollit anim id est laborum.  ";

sub lorem_ipsum :Export(lorem_ipsum lorem) {
	my ($reldata, $args, $size)= @_;
	$size= $args->{size} if !defined $size && $args && defined $args->{size};
	return $lorem_ipsum_classic
		unless defined $size;
	my $ret= $lorem_ipsum_classic x int(1+($size/length $lorem_ipsum_classic));
	substr($ret, 0, $size);
}

1;
