#!/usr/bin/env perl

do './locale.pl';
use IO::Socket qw(:all);
#BUILD_CUT DO NOT REMOVE 

add_param("server host", \our $server_host, "Host of the target server");
add_param("server port", \our $server_port, "Port of the target server");
add_param("proxy host", \our $proxy_host, "Host of the external proxy");
add_param("proxy port", \our $proxy_port, "Port of the external proxy");
add_opt("T", \our $timeout, "sec", 5, "Set timeout on the connections");
parse_opts();

our (%store_map, %store_unmap, %store_time);
our ($last_time) = undef;
our ($ln_primary);
our ($lns) = IO::Select->new();

# Convert UUID into a socket
# Arguments
#   1: Address
sub client_convert {
	unless (defined $store_map{$_[0]}) {
		v_echo("Connecting client $_[0]");
		my $ln_client = socket_connect("Line at", IPPROTO_UDP, $server_host, $server_port);
		$lns->add($ln_client);
		$store_map{$_[0]} = $ln_client;
		$store_unmap{$ln_client} = $_[0];
	}
	$store_time{$_[0]} = time + $timeout;
	$_[0] = $store_map{$_[0]};
}

# Convert socket into a UUID
# Arguments
#   1: Socket
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
			$lns->remove($mapped);
			$mapped->close();
			v_echo("Connection $key timed out");
		} else {
			$new_time = $client_time if (!defined $new_time) || ($new_time > $client_time);
		}
	}
	$last_time = $new_time;
}

# Receive data from proxy
# Arguments
#   1: Address
#   2: Size
sub receive_data {
	v_echo("Got data from the proxy: UUID - '$_[0]', Size - $_[1]");
	client_convert($_[0]);
	$ln_primary->read(my $s_data, $_[1]);
	$_[0]->send($s_data, 0);
}

# Send data to proxy in format "<address> <size>\n<datagram>"
# Arguments
#   1: Socket
sub transmit_data {
	$_[0]->recv(my $s_data, 65535);
	client_revert($_[0]);
	v_echo("Got data for the proxy: UUID - '$_[0]', Size - " . length($s_data));
	return unless defined $_[0];
	$ln_primary->printf("%s %d\n", $_[0], length($s_data));
	$ln_primary->print($s_data);
}

# Set trap for shutdown
$SIG{TERM} = $SIG{INT} = sub { exit_close("Server killed, exiting", $ln_primary, values %store_map); };

# Initiate sockets
$ln_primary = socket_connect("Connecting to proxy at", IPPROTO_TCP, $proxy_host, $proxy_port);
$ln_primary->autoflush(1);

$lns->add($ln_primary);

while (1) {
	my @lns_ready = (defined $last_time) ? $lns->can_read($last_time - time()) : $lns->can_read();
	foreach my $ln_ready (@lns_ready) {
		unless ($ln_ready == $ln_primary) { # Data available on the client socket
			transmit_data($ln_ready);
		} else { # Data available on the proxy socket
			my $s_meta = <$ln_primary>;
			exit_close("Proxy disconnected, exiting", $ln_primary, values %store_map) unless defined $s_meta;
			receive_data($s_meta =~ /^(\S+)\s+(\S+)\s*/);
		}
	}
	client_cleanup() if ((%store_time) && ($last_time <= time()));
}
