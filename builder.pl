#!/usr/bin/env perl

my ($shared) = "./locale.pl";
my (@executables) = ("udp_multiplex.pl", "udp_demultiplex.pl", "tcp_multiplex.pl", "tcp_demultiplex.pl");

open(my $shared_fd, "<", $shared);
mkdir "build/";

for my $exe_name (@executables) {
	open(my $exec_fd, "<", $exe_name);
	open(my $result_fd, ">", "build/".$exe_name);
	seek($shared_fd, 0, 0);
	while (my $line = <$shared_fd>) {
		chomp($line);
		print $result_fd $line."\n";
	}
	my $found = 0;
	while (my $line = <$exec_fd>) {
		unless ($found) {
			$found = 1 if $line =~ /^#BUILD_CUT/;
			next;
		}
		chomp($line);
		print $result_fd $line."\n";
	}
	close($exec_fd);
	close($result_fd);
	chmod 0755, "build/".$exe_name;
}

close($shared_fd);
