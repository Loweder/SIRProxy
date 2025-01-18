#!/usr/bin/env perl

do './locale.pl';
use IO::Socket qw(:all);
#BUILD_CUT DO NOT REMOVE 

use threads;

add_param("server host", \our $server_host, "Host of the target server");
add_param("server port", \our $server_port, "Port of the target server");
add_param("proxy host", \our $proxy_host, "Host of the external proxy");
add_param("proxy metaport", \our $proxy_metaport, "Port of the external proxy used for metadata");
add_param("proxy dataport", \our $proxy_dataport, "Port of the external proxy used for data lines");
parse_opts();

our $ln_metadata;

# Attach a client
# Arguments:
#   1: Address
sub attach {
	threads->create({'exit' => 'thread_only'}, sub {
			my ($s_addr) = @_;
			my ($ln_server, $ln_proxy);

			# Set trap for thread shutdown
			$SIG{TERM} = sub { exit_close("Connection $s_addr closed", $ln_server, $ln_proxy); };

			# Initiate thread sockets
			v_echo("Connecting client $s_addr");
			$ln_server = socket_connect("Server line at", IPPROTO_TCP, $server_host, $server_port);
			$ln_proxy = socket_connect("Proxy line at", IPPROTO_TCP, $proxy_host, $proxy_dataport);
			socket_adjust($ln_server, $ln_proxy);

			my $lns = IO::Select->new($ln_server, $ln_proxy);

			$ln_proxy->print($s_addr, "\n");

			while (1) {
				my @lns_ready = $lns->can_read();
				foreach my $ln_ready (@lns_ready) {
					my $ln_target = $ln_ready == $ln_server ? $ln_proxy : $ln_server;
					my $count = 0;
					do {
						$count = $ln_ready->sysread(my $buffer, 4096);
						$ln_target->print($buffer);
					} while ($count > 0);
					exit_close("Connection $s_addr closed", $ln_server, $ln_proxy) if defined $count;
				}
			}
		}, @_);
}

# Set trap for shutdown
$SIG{TERM} = $SIG{INT} = sub {
	$_->kill('TERM')->detach() foreach threads->list();
	exit_close("Server killed, exiting", $ln_metadata); 
};

# Initiate sockets
$ln_metadata = socket_connect("Connecting to proxy meta at", IPPROTO_TCP, $proxy_host, $proxy_metaport);

while (1) {
	chomp(my $s_addr = <$ln_metadata>);
	unless (defined $s_addr) {
		$_->kill('TERM')->detach() foreach threads->list();
		exit_close("Proxy disconnected, exiting", $ln_metadata); 
	}
	attach($s_addr);
}
