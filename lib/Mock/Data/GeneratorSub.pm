package Mock::Data::GeneratorSub;
require Mock::Data::Generator;
our @ISA= ( 'Mock::Data::Generator' );

# ABSTRACT: Wrap a coderef to become a blessed Generator object
# VERSION

=head1 DESCRIPTION

This is an implementation detail of L<Mock::Data::Generator>.  It gives a coderef the API of
a L<Mock::Data::Generator> by blessing it.

=head1 CONSTRUCTOR

=head2 new

Blesses a coderef, which is the only argument.

=head1 METHODS

=head2 compile

Slightly optimized version of L<Mock::Data::Generator/compile>

=head2 generate

Calls C<$self>.

=cut

sub new {
	Scalar::Util::reftype($_[1]) eq 'CODE' or Carp::croak("Not a coderef");
	bless $_[1], __PACKAGE__;
}

sub compile {
	my $self= shift;
	return $self unless @_;
	# Else wrap arguments in a new coderef
	my @default= @_;
	my $default_opts_hash= @default && ref $default[0] eq 'HASH'? $default[0] : undef;
	return bless sub {
		my $mock= shift;
		return $self->($mock, @default) unless @_;
		# Merge any options-by-name newly supplied with options-by-name from @default
		unshift @_, (ref $_[0] eq 'HASH')? { %{$default_opts_hash}, %{shift @_} } : $default_opts_hash
			if $default_opts_hash;
		return $self->($mock, @_);
	}, __PACKAGE__;
}

sub generate {
	shift->(@_);
}

1;
