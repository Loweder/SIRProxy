#!/usr/bin/env perl

do './locale.pl';

use threads;
use IO::Socket qw(:all);
use IO::Select;

add_param("server metaport", \our $server_metaport, "Port from which the server will receive metadata");
add_param("server dataport", \our $server_dataport, "Port to which the server will connect data lines");
add_param("client port", \our $client_port, "Port to which the clients will connect");
add_opt("a", \our $anonymise, 0, "Anonymise clients");
parse_opts();

our (%store_map);
our ($ln_metadata, $ln_server, $ln_client);

sub client_attach {
	my $ln_a = $ln_client->accept() or return;
	my $encoded = $anonymise ? $last_id++ . "-RANDOM-" . int(rand(32767)) : $ln_a->peerhost().":".$ln_a->peerport();
	$store_map{$encoded} = $ln_a;
	$ln_metadata->print($encoded, "\n");
	v_echo("Connecting a client line $encoded");
};

sub server_attach {
	my $ln_a = $ln_server->accept() or return;
	chomp(my $s_addr = <$ln_a>);
	unless (defined $s_addr && defined $store_map{$s_addr}) {
		$ln_a->close();
		return;
	}
	threads->create({'exit' => 'thread_only'}, sub {
			my ($s_addr, $ln_server, $ln_client) = @_;
			$SIG{TERM} = sub {
				v_echo("Connection killed at $s_addr");
				exit_close($ln_server, $ln_client);
			};
			$ln_server->autoflush(1);
			$ln_server->blocking(0);
			$ln_client->autoflush(1);
			$ln_client->blocking(0);
			my $lns = IO::Select->new($ln_server, $ln_client);
			while (1) {
				my @lns_ready = $lns->can_read();
				foreach my $ln_ready (@lns_ready) {
					my $ln_target = $ln_ready == $ln_server ? $ln_client : $ln_server;
					my $count = 0;
					do {
						$count = $ln_ready->sysread(my $buffer, 4096);
						$ln_target->print($buffer);
					} while ($count > 0);
					if (defined $count) {
						v_echo("Connection closed at $s_addr");
						exit_close($ln_server, $ln_client);
					}
				}
			}

		}, $s_addr, $ln_a, delete $store_map{$s_addr});
	v_echo("Connecting a server line $s_addr");
}

$SIG{TERM} = $SIG{INT} = sub {
	v_echo("Proxy killed, exiting");
	$_->kill('TERM')->detach() foreach threads->list();
	exit_close($ln_metadata, $ln_server, $ln_client); 
};

#Initiate sockets
my $ln_metalisten = IO::Socket::INET->new(
	Proto => IPPROTO_TCP,
	LocalHost => inet_ntoa(INADDR_ANY),
	LocalPort => $server_metaport,
	ReuseAddr => 1,
	Listen => 1,
) or die "Server meta failed to create: $@";
$ln_server = IO::Socket::INET->new(
	Proto => IPPROTO_TCP,
	LocalHost => inet_ntoa(INADDR_ANY),
	LocalPort => $server_dataport,
	ReuseAddr => 1,
	Listen => 10,
) or die "Server data line failed to create: $@";
$ln_client = IO::Socket::INET->new(
	Proto => IPPROTO_TCP,
	LocalHost => inet_ntoa(INADDR_ANY),
	LocalPort => $client_port,
	ReuseAddr => 1,
	Listen => 10,
) or die "Client line failed to create: $@";

$ln_metadata = $ln_metalisten->accept() or die "Server meta accept failed: $!";
close($ln_metalisten);

$ln_metadata->autoflush(1);
$ln_metadata->blocking(0);

my $lns = IO::Select->new($ln_metadata, $ln_server, $ln_client);

while (1) {
	my @lns_ready = $lns->can_read();
	foreach my $ln_ready (@lns_ready) {
		if ($ln_ready == $ln_client) {
			client_attach();
		} elsif ($ln_ready == $ln_server) {
			server_attach();
		} elsif ($ln_ready == $ln_metadata) {
			my $count = 0;
			do {
				$count = $ln_metadata->sysread(my $discard, 4096);
			} while ($count > 0);
			if (defined $count) {
				v_echo("Server disconnected, exiting");
				$_->kill('TERM')->detach() foreach threads->list();
				exit_close($ln_metadata, $ln_server, $ln_client); 
			}
		}
	}
}
