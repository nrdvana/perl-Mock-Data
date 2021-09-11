package Mock::Data::Plugin::Net;
use Mock::Data::Plugin -exporter_setup => 1;
our @generators= qw( ipv4 cidr macaddr );
export(@generators);

=head1 SYNOPSIS

  $mock= Mock::Data->new(['Net']);
  $mock->ipv4;     #  "127.54.23.132"
  $mock->cidr;     #  "127.43.0.0/16"
  $mock->macaddr;  #  "fc:34:23:98:13:53"

=head1 DESCRIPTION

This produces some simple patterns for network addresses.  It produces private IP ranges
and private MAC addresses.  Patches welcome for additional features.

=cut

sub apply_mockdata_plugin {
	my ($class, $mock)= @_;
	$mock->add_generators(
		map +("Net::$_" => $class->can($_)), @generators
	);
}

=head1 GENERATORS

=head2 inet

Return a random IP address within C<< 127.0.0.0/8 >>, excluding .0 and .255

=cut

sub ipv4 {
	sprintf "127.%d.%d.%d", rand 256, rand 256, 1+rand 254;
}

=head2 cidr

Return a random CIDR starting with C<< 127. >> like C<< 127.0.42.0/24 >>

=cut

sub cidr {
	my $blank= 1 + int rand 23;
	my $val= (int rand(1<<(24 - $blank))) << $blank;
	sprintf '127.%d.%d.%d/%d', (unpack 'C4', pack 'N', $val)[1,2,3], 32 - $blank;
}

=head2 macaddr

Return a random ethernet MAC in XX:XX:XX:XX:XX:XX format, taken from the Locally Administered
Address Ranges.

=cut

sub macaddr {
	sprintf '%02x:%02x:%02x:%02x:%02x:%02x',
		((rand 64)<<2) | 0x02, rand 256, rand 256,
		rand 256, rand 256, rand 256
}

1;
