package Mock::Data::Plugin::Text;
use strict;
use warnings;
use Carp;
use Scalar::Util 'blessed';
use Mock::Data::Charset;
require Exporter;
our @ISA= ( 'Exporter' );
our @EXPORT_OK= qw( word words lorem_ipsum join );

# ABSTRACT: Mock::Data plugin that provides text-related generators
# VERSION

=head1 SYNOPSIS

  my $mockdata= Mock::Data->new(['Text']);
  
  # Strings of /(\w+ )+/
  $mockdata->words($len)            # up to $size characters
  
  # classic boilerplate
  $mockdata->lorem_ipsum($len)

  # Build strings of words
  $mockdata->join({ source => '{lorem_ipsum}', sep => '<p>', count => 5 });

=head1 DESCRIPTION

This plugin for L<Mock::Data> generates simple text patterns.  It may be expanded to support
multiple languages in the future.

=cut

sub apply_mockdata_plugin {
	my ($class, $mockdata)= @_;
	$mockdata->merge_generators(
		join => \&join,
		'Text::join' => \&join,
		word => \&word,
		'Text::word' => \&word,
		words => \&words,
		'Text::words' => \&words,
		lorem_ipsum => \&lorem_ipsum,
		'Text::lorem_ipsum' => \&lorem_ipsum,
	);
}

=head1 GENERATORS

=head2 join

  $mockdata->join( $sep, $source, $count ); # concatenate strings from generators
  $mockdata->join( \%options );

This generator concatenates the output of other generators.  If the generators return arrays,
the elements will become part of the list to concatenate.  The generator can either concatenate
everything, or concatenate up to a size limit, calling the generators repeatedly until it
reaches the goal.

=over

=item sep

The separator; defaults to a space.

=item source

One or more generators.  They will be coerced to generators if they are not already.

=item count

The number of times to call each generator.  This defaults to 1.

=item len

The string length goal.  The generators will be called repeatedly until this lenth is reached.

=item max_len

The string length maximum.  If the output is longer than this, it will be truncated, and the
final separator will be removed if the string would otherwise end with a separator.

=back

=cut

sub join {
	
	...
}

=head2 word

  $mockdata->word;

This generator returns one "word" which is roughly C<< /\w{1,11}/a >> but distributed more
heavily around 5 characters.

=head2 words

  $mockdata->words($max_len);

This is an alias for C<< ->join({ source => '{word}', len => $max_len, max_len => $max_len }) >>.
It takes the same options as L</join>.

=back

=cut

our $word_generator= Mock::Data::Charset->new(
	notation => 'a-z',
	str_len => sub { 1 + int(rand 3 + rand 3 + rand 4) }
);
*word= $word_generator->compile;

sub words {
	my $mockdata= shift;
	my %opts= @_ && ref $_[0] eq 'HASH'? %{ shift() } : ();
	$opts{len}= $opts{max_len}= shift if @_;
	$opts{source} //= $mockdata->generators->{word};

	$mockdata->generators->{join}->($mockdata, \%opts);
}

=head2 lorem_ipsum

  $mockdata->lorem_ipsum($len)
  $mockdata->lorem_ipsum({ len => $len })

Repetitions of the classic 1500's Lorem Ipsum text up to length C<len>

The default length is one iteration of the string.

=cut

my $lorem_ipsum_classic=
 "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor "
."incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis "
."nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.  "
."Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu "
."fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in "
."culpa qui officia deserunt mollit anim id est laborum.  ";

sub lorem_ipsum {
	my $mockdata= shift;
	my $len= @_ > 1? $_[1] : !ref $_[0]? $_[0] : ref $_[0] eq 'HASH'? $_[0]{len} : undef;
	return $lorem_ipsum_classic
		unless defined $len;
	my $ret= $lorem_ipsum_classic x int(1+($len/length $lorem_ipsum_classic));
	substr($ret, $len)= '';
	$ret =~ s/\s+$//;
	return $ret;
}

1;
