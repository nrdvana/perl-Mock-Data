package Mock::Data::SubWrapper;
use strict;
use warnings;
require Scalar::Util;
require Mock::Data::Generator;
our @ISA= ( 'Mock::Data::Generator' );

# ABSTRACT: Wrap a coderef to become a blessed Generator object
# VERSION

=head1 DESCRIPTION

This is an implementation detail of L<Mock::Data::Generator>.  It wraps coderefs to be
generators without bothering to allocate a new object for them.

=head1 METHODS

=head2 compile

Returns C<$self>.  (because it's already a coderef)

=head2 generate

Calls C<$self>.

=cut

sub _new {
	my ($pkg, $sub)= @_;
	bless $sub, $pkg;
}

sub compile {
	return $_[0];
}

sub generate {
	my $self= shift;
	$self->(@_);
}

1;
