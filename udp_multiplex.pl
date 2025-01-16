#!/usr/bin/env perl
#TODO make Bash part init before functions
#Also: add verbose logging

do './locale.pl';

use IO::Socket qw(:all);
use IO::Select;

add_param("server port", \our $server_port, "Port to which the server will connect");
add_param("client port", \our $client_port, "Port to which the clients will connect");
add_opt("T", \our $timeout, "sec", 5, "Set timeout on the connections");
add_opt("a", \our $anonymise, 0, "Anonymise clients");
parse_opts();

our (%store_map, %store_unmap, %store_time);
our ($last_id, $last_time) = (0, undef);
our ($ln_primary, $ln_client);

# Convert packed address into a UUID
# Arguments
#   1: Address
sub client_convert {
	unless (defined $store_map{$_[0]}) {
		my ($port, $addr) = sockaddr_in($_[0]);
		my $encoded = $anonymise ? $last_id++ . "-RANDOM-" . int(rand(32767)) : inet_ntoa($addr) . ":$port";
		$store_map{$_[0]} = $encoded;
		$store_unmap{$encoded} = $_[0];
		v_echo("Connecting a client $encoded");
	}
	$store_time{$_[0]} = time + $timeout;
	$_[0] = $store_map{$_[0]};
}

# Convert UUID into a packed address
# Arguments
#   1: Address
sub client_revert {
	$_[0] = $store_unmap{$_[0]};
	$store_time{$_[0]} = time + $timeout;
}

# Cleanup timed-out clients
sub client_cleanup {
	my $new_time = undef;
	my $cur_time = time();
	foreach my $key (keys %store_time) {
		my $client_time = $store_time{$key};
		if ($client_time < $cur_time) {
			my $mapped = delete $store_map{$key};
			delete $store_unmap{$mapped};
			delete $store_time{$key};
			v_echo("Client timed out at $mapped");
		} else {
			$new_time = $client_time if (!defined $new_time) || ($new_time > $client_time);
		}
	}
	$last_time = $new_time;
}

# Receive data from server
# Arguments
#   1: Address
#   2: Size
sub receive_data {
	v_echo("Got data from server: UUID - '$_[0]', Size - $_[1]");
	client_revert($_[0]);
	$ln_primary->read(my $s_data, $_[1]);
	$ln_client->send($s_data, 0, $_[0]) if defined $_[0];
}

# Send data to server in format "<address> <size>\n<datagram>"
sub transmit_data {
	my $s_addr = $ln_client->recv(my $s_data, 65535);
	return unless defined $s_addr;
	client_convert($s_addr);
	v_echo("Got data to server: UUID - '$s_addr', Size - " . length($s_data));
	$ln_primary->printf("%s %d\n", $s_addr, length($s_data));
	$ln_primary->print($s_data);
}

#Set trap for shutdown
$SIG{TERM} = $SIG{INT} = sub { exit_close($ln_primary, $ln_client); };

#Initiate sockets
my $ln_listener = IO::Socket::INET->new(
	Proto => IPPROTO_TCP,
	LocalHost => inet_ntoa(INADDR_ANY),
	LocalPort => $server_port,
	ReuseAddr => 1,
	Listen => 1,
) or die "Server line failed to create: $@";
$ln_client = IO::Socket::INET->new(
	Proto => IPPROTO_UDP,
	LocalHost => inet_ntoa(INADDR_ANY),
	LocalPort => $client_port,
	ReuseAddr => 1,
) or die "Client line failed to create: $@";

$ln_primary = $ln_listener->accept() or die "Server line accept failed: $!";
close($ln_listener);

$ln_primary->autoflush(1);

my $lns = IO::Select->new($ln_primary, $ln_client);

while (1) {
	my @lns_ready = (defined $last_time) ? $lns->can_read($last_time - time()) : $lns->can_read();
	foreach my $ln_ready (@lns_ready) {
		if ($ln_ready == $ln_client) { #Data available on the client socket
			transmit_data();
		} elsif ($ln_ready == $ln_primary) { #Data available on the server socket
			my $s_meta = <$ln_primary>;
			unless (defined $s_meta) {
				v_echo("Server disconnected, exiting");
				exit_close($ln_primary, $ln_client);
			}
			receive_data($s_meta =~ /^(\S+)\s+(\S+)\s*/);
		}
	}
	client_cleanup() if ((%store_time) && ($last_time <= time()));
}
