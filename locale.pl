#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Std;
use IO::Socket qw(:all);
use IO::Select;

# Those variables are used internally for option parsing
our (@com_params, @com_flags, @com_options);
our (%com_data);
our ($com_maxopt, $com_maxpar) = (0, 0);

# Add an option/flag
# 4 arguments if flag, 5 otherwise
# Arguments:
#   10-1f: Name
#   2o-2f: Variable
#   3o-#f: Value name
#   4o-3f: Default value
#   5o-4f: Description
sub add_opt {
	if (scalar(@_) <= 4) {
		push(@com_flags, $_[0]);
		$com_data{$_[0] . '-var'} = $_[1];
		$com_data{$_[0] . '-desc'} = $_[3];
		${$_[1]} = $_[2];
	} else {
		push(@com_options, $_[0]);
		$com_data{$_[0] . '-var'} = $_[1];
		$com_data{$_[0] . '-arg'} = $_[2];
		$com_data{$_[0] . '-desc'} = $_[4];
		${$_[1]} = $_[3];
		$com_maxopt = length($_[2]) if $com_maxopt < length($_[2]);
	}
}

# Add a positional argument
# Arguments:
#   1: Name
#   2: Variable
#   3: Description
sub add_param {
	push(@com_params, $_[0]);
	$com_data{$_[0] . '-var'} = $_[1];
	$com_data{$_[0] . '-desc'} = $_[2];
	${$_[1]} = undef;
	$com_maxpar = length($_[0]) if $com_maxpar < length($_[0]);
}

# Add default options
add_opt("v", \our $com_verbose, 0, "Verbose output (debugging)");
add_opt("h", \our $com_help, 0, "Display this message");

# "Verbose" echo: only echo on "-v"
sub v_echo {
  print "@_\n" if $com_verbose;	
}

# Show usage on invalid syntax
sub show_usage {
	print "Usage: $0 ";

	# Display flags as "[-abc]"
	print "[-" . join("", @com_flags) . "] ";

	# Display options as "[-a <arg>] [-b <arg>]"
	print "[-$_ <$com_data{$_ . '-arg'}>] " foreach @com_options;

	# Display positional arguments as "<arg1> <arg2>"
	print "<$_> " foreach @com_params;
	print "\n";
	exit 1;
}

# Show help on "-h"
sub show_help {
	print "$0 ";

	# Display flags as "[-abc]"
	print "[-" . join("", @com_flags) . "] ";

	# Display options as "[-a <arg>] [-b <arg>]"
	print "[-$_ <$com_data{$_ . '-arg'}>] " foreach @com_options;

	# Display positional arguments as "<arg1> <arg2>"
	print "<$_> " foreach @com_params;
	print "\n";

	# Display positional arguments as "  <arg> Description"
	printf "  %-*s  %s\n", $com_maxpar + 2, "<$_>", $com_data{$_ . '-desc'} foreach @com_params;

	print "Options:\n";

	# Display flags as "  -a Description"
	printf "  -%-*s  %s\n", $com_maxopt + 4, $_, $com_data{$_ . '-desc'} foreach @com_flags;

	# Display options as "  -a <arg> Description"
	printf "  -%-*s  %s\n", $com_maxopt + 4, "$_ <$com_data{$_ . '-arg'}>", $com_data{$_ . '-desc'} foreach @com_options;

	exit;
}

# Parse arguments
sub parse_opts {
	my $opts = "";
	$opts .= join("", @com_flags);
	$opts .= join(":", @com_options) . ":" if @com_options;

	# Parse options
	show_usage() unless getopts($opts, \my %names);

	# Iterate over each option
	foreach my $name (keys %names) {
		${$com_data{$name . '-var'}} = $names{$name};
		show_usage() unless defined($names{$name});
	}

	show_help() if $com_help;

	# Prepare for parsing positional arguments
	if (scalar(@ARGV) != scalar(@com_params)) {
		print "$0: " . scalar(@com_params) . " positional arguments required\n";
		show_usage();
	}

	for my $param (@com_params) {
		${$com_data{$param . '-var'}} = shift @ARGV;
	}
}

# Start a binding socket
# Arguments:
#   1: Message
#   2: Connection type
#   3: Connection port
#   4: Listening queue
sub socket_bind {
	v_echo "$_[0] $_[2]";
	my @args = (
		Proto => $_[1],
		LocalHost => inet_ntoa(INADDR_ANY),
		LocalPort => $_[2],
		ReuseAddr => 1,
	);
	push @args, (Listen => $_[3]) if scalar(@_) > 3;
	return (IO::Socket::INET->new(@args) or die "Failed to bind to $_[2]");
}

# Start a connecting socket
# Arguments:
#   1: Message
#   2: Connection type
#   3: Connection address
#   4: Connection port
sub socket_connect {
	v_echo "$_[0] $_[2]:$_[3]";
	return (IO::Socket::INET->new(
		Proto => $_[1],
		PeerHost => $_[2],
		PeerPort => $_[3],
	) or die "Failed to connect to $_[2]:$_[3]");
}

# Configure all passed sockets to autoflush/nonblock
sub socket_adjust {
	for my $sock (@_) {
		$sock->autoflush(1);
		$sock->blocking(0);
	}
}

# Close all sockets, and exit
# Arguments:
#   1: Message
#   2+: FDs to close
sub exit_close {
	my ($message, @rest) = @_;
	v_echo($message);
	foreach my $sock (@rest) {
		close($sock);
	}
	exit;
}
