#!/usr/bin/env perl

do './locale.pl';
use IO::Socket qw(:all);
#BUILD_CUT DO NOT REMOVE 

use threads;

add_param("server metaport", \our $server_metaport, "Port from which the server will receive metadata");
add_param("server dataport", \our $server_dataport, "Port to which the server will connect data lines");
add_param("client port", \our $client_port, "Port to which the clients will connect");
add_opt("a", \our $anonymise, 0, "Anonymise clients");
parse_opts();

our (%store_map);
our ($ln_metadata, $ln_server, $ln_client);

# Attach a client line
sub client_attach {
	my $ln_a = $ln_client->accept() or return;
	my $encoded = $anonymise ? $last_id++ . "-RANDOM-" . int(rand(32767)) : $ln_a->peerhost().":".$ln_a->peerport();
	$store_map{$encoded} = $ln_a;
	$ln_metadata->print($encoded, "\n");
	v_echo("Connecting client $encoded");
};

# Attach a server line
sub server_attach {
	my $ln_a = $ln_server->accept() or return;
	chomp(my $s_addr = <$ln_a>);
	unless (defined $s_addr && defined $store_map{$s_addr}) {
		$ln_a->close();
		return;
	}
	threads->create({'exit' => 'thread_only'}, sub {
			my ($s_addr, $ln_server, $ln_client) = @_;

			$SIG{TERM} = sub { exit_close("Connection $s_addr killed", $ln_server, $ln_client); };

			v_echo("Accept client $s_addr");
			socket_adjust($ln_server, $ln_client);

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
					exit_close("Connection $s_addr closed", $ln_server, $ln_client) if defined $count;
				}
			}
		}, $s_addr, $ln_a, delete $store_map{$s_addr});
}

# Set trap for shutdown
$SIG{TERM} = $SIG{INT} = sub {
	$_->kill('TERM')->detach() foreach threads->list();
	exit_close("Proxy killed, exiting", $ln_metadata, $ln_server, $ln_client); 
};

# Initiate sockets
my $ln_metalisten = socket_bind("Listening for server meta at", IPPROTO_TCP, $server_metaport, 1);
$ln_server = socket_bind("Listening for server lines at", IPPROTO_TCP, $server_dataport, 10);
$ln_client = socket_bind("Listening for client lines at", IPPROTO_TCP, $client_port, 10);
$ln_metadata = $ln_metalisten->accept() or die "Server meta accept failed: $!";
close($ln_metalisten);
socket_adjust($ln_metadata);

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
				$_->kill('TERM')->detach() foreach threads->list();
				exit_close("Server disconnected, exiting", $ln_metadata, $ln_server, $ln_client); 
			}
		}
	}
}
