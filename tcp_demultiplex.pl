#!/usr/bin/env perl

do './locale.pl';

use threads;
use IO::Socket qw(:all);
use IO::Select;

add_param("server host", \our $server_host, "Host of the target server");
add_param("server port", \our $server_port, "Port of the target server");
add_param("proxy host", \our $proxy_host, "Host of the external proxy");
add_param("proxy metaport", \our $proxy_metaport, "Port of the external proxy used for metadata");
add_param("proxy dataport", \our $proxy_dataport, "Port of the external proxy used for data lines");
parse_opts();

sub attach {
	threads->create({'exit' => 'thread_only'}, sub {
			my ($s_addr) = @_;
			my ($ln_server, $ln_proxy);

			#Set trap for thread shutdown
			$SIG{TERM} = sub {
				v_echo("Connection killed at $s_addr");
				exit_close($ln_server, $ln_proxy);
			};

			#Initiate thread sockets
			$ln_server = IO::Socket::INET->new(
				Proto => IPPROTO_TCP,
				PeerHost => $server_host,
				PeerPort => $server_port,
			) or die "Server line failed to create: $@";
			$ln_proxy = IO::Socket::INET->new(
				Proto => IPPROTO_TCP,
				PeerHost => $proxy_host,
				PeerPort => $proxy_dataport,
			) or die "Proxy line failed to create: $@";

			$ln_server->autoflush(1);
			$ln_server->blocking(0);
			$ln_proxy->autoflush(1);
			$ln_proxy->blocking(0);
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
					if (defined $count) {
						v_echo("Connection closed at $s_addr");
						exit_close($ln_server, $ln_proxy);
					}
				}
			}
		}, @_);
}

#Set trap for shutdown
$SIG{TERM} = $SIG{INT} = sub {
	v_echo("Proxy killed, exiting");
	$_->kill('TERM')->detach() foreach threads->list();
	exit_close($ln_metadata); 
};

#Initiate sockets
$ln_metadata = IO::Socket::INET->new(
	Proto => IPPROTO_TCP,
	PeerHost => $proxy_host,
	PeerPort => $proxy_metaport,
) or die "Proxy meta failed to create: $@";

while (1) {
	chomp(my $s_addr = <$ln_metadata>);
	unless (defined $s_addr) {
		v_echo("Proxy disconnected, exiting");
		$_->kill('TERM')->detach() foreach threads->list();
		exit_close($ln_metadata); 
	}
	attach($s_addr);
}
