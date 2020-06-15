package Mock::Data::Generator::SubWrapper;
use strict;
use warnings;
require Scalar::Util;
require Mock::Data::Generator;
our @ISA= ( 'Mock::Data::Generator' );
use overload '""' => sub { shift->to_string };

=head1 DESCRIPTION

This is an implementation detail of L<Mock::Data::Generator>.  It wraps coderefs to be
generators without bothering to allocate a new object for them.  It also allows compiled
templates to be stringified so you can see what the template was.

=head1 ATTRIBUTES

=head2 template

The original template string if known, else C<undef>.

=head1 METHODS

=head2 compile

Returns C<$self>.  (because it's already a coderef)

=head2 evaluate

Calls C<$self>.

=head2 to_string

Returns a useful notation to indicate that this is an object, a coderef, and what the
original template was, if any.

=cut

our %sub_attrs;

sub _new {
	my ($pkg, $sub, $attrs)= @_;
	$sub_attrs{Scalar::Util::refaddr $sub}= $attrs
		if $attrs;
	bless $sub, $pkg;
}

sub template {
	my $attrs= $sub_attrs{Scalar::Util::refaddr $_[0]};
	return $attrs? $attrs->{template} : undef;
}

sub compile {
	return $_[0];
}

sub evaluate {
	shift->(@_);
}

sub to_string {
	my $self= shift;
	my $tpl= $self->template;
	defined $tpl? ref($self) . '=(Tpl: "$tpl")'
		: ref($self) . '=CODE(' . Scalar::Util::refaddr($self) . ')'
}

sub DESTROY {
	delete $sub_attrs{Scalar::Util::refaddr $_[0]};
}

1;
