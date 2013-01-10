#!/usr/bin/perl -w

# check_sun_cluster - Nagios plugin to check the status of a 
# Sun Cluster (version 3.2 or greater)

use POSIX;
use strict;
use lib utils.pm;
use utils qw($TIMEOUT %ERRORS &support);
use Getopt::Long;
use vars qw($timeout $opt_V $opt_h $opt_nodes $opt_quorum $opt_transport $opt_groups $opt_resources $opt_all $cluster_binary);

my $PROGNAME = "check_sun_cluster";
my $VERSION = "1.0";
my $BIN_PATH = "/usr/cluster/bin";

sub print_help();
sub print_usage();
sub process_arguments();

### Validate Arguments
my $status = process_arguments();

# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
	print ("ERROR: No response from sun cluster (alarm)\n");
	exit $ERRORS{"UNKNOWN"};
};
alarm($timeout);

## Check nodes (option -n)
#
# Check the status of the cluster nodes.
# Status check:
#    - Online  -> [ OK ]
#    - Offline -> [ CRITICAL ]
#

if (($opt_nodes) or ($opt_all)){
        open (NODE_STATUS, "$cluster_binary/clnode status |")
                or die "Couldn't execute program: $!";
        while (<NODE_STATUS>){
                next unless /(Node Name)/;
                my $match = $1;
                print "[$match]\n";
                my $line = <NODE_STATUS>; # discard dashes
                while (!eof){
                        if ( !(($line=<NODE_STATUS>) =~ /^\s*$/) ){
                                print "read: $line";
                        }
                }
        }
        close(NODE_STATUS);
}

## Check quorum (option -q)
#
# Check the status and vote counts of quorum devices.
# Node status  Service status
# -----------  -------------
#   Online   -> [ OK ]
#   Offline  -> [ CRITICAL ]
#
# Votes are not checked
#    

if (($opt_quorum) or ($opt_all)){
        open (QUORUM_STATUS, "$cluster_binary/clquorum status |")
                or die "Couldn't execute program: $!";
        while (<QUORUM_STATUS>){
                next unless /((Needed)|(Node Name)|(Device Name))/;
                my $match = $1;
                print "[$match]\n";
                my $line = <QUORUM_STATUS>; # discard dashes

                # useless label to remark that this is a case statement in disguise
                CASES:
                "Needed" eq $match && do {
                        $line=<QUORUM_STATUS>;
                        print "read: $line";
                        next;
                };
                "Node Name" eq $match && do {
                        while ( ! (($line=<QUORUM_STATUS>) =~ /^\s*$/) ){
                                print "read: $line";
                        }
                };
                "Device Name" eq $match && do {
                        while ( ! (($line=<QUORUM_STATUS>) =~ /^\s*$/) ){
                                print "read: $line";
                        }
                };
        }
        close(QUORUM_STATUS);
}

## Check transport paths (option -t)
#
# Check the status of the interconnect paths.
#
# Transport status  Service status
# ----------------  --------------
#   Path online   -> [ OK ]
#   waiting       -> [ WARNING ]
#   faulted       -> [ CRITICAL ]
#

if (($opt_transport) or ($opt_all)){
        open (TRANSPORT_STATUS, "$cluster_binary/clintr status |")
                or die "Couldn't execute program: $!";
        while (<TRANSPORT_STATUS>){
                next unless /(Endpoint)/;
                my $match = $1;
                print "[$match]\n";
                my $line = <TRANSPORT_STATUS>; # discard dashes
                while (!eof){
                        if ( ! (($line=<TRANSPORT_STATUS>) =~ /^\s*$/) ){
                                print "read: $line";
                        }
                }
        }
        close(TRANSPORT_STATUS);
}

## Check resource groups (option -g)
#
# Check status for resource groups
#
# Resources status  Service status
# ----------------  --------------
#   Degraded      -> [ CRITICAL ]
#   Faulted       -> [ CRITICAL ]
#   Offline       -> [ CRITICAL ]
#   Online        -> [ OK ]
#   Unknown       -> [ WARNING ]
#

if (($opt_groups) or ($opt_all)){
        open (GROUP_STATUS, "$cluster_binary/clrg status |")
                or die "Couldn't execute program: $!";
        while (<GROUP_STATUS>){
                next unless /(Group Name)/;
                my $match = $1;
                print "[$match]\n";
                my $line = <GROUP_STATUS>; # discard dashes
                while (!eof){
                        if ( ! (($line=<GROUP_STATUS>) =~ /^\s*$/) ){
                               print "read: $line";
                        }
                }
        }
        close(GROUP_STATUS);
}

## Check resources (option -r)
#
# Check the status of the resources.
#
# Resources status       Service status
# ----------------       --------------
# Online               -> [ OK ]
# Offline              -> [ CRITICAL ]
# Start_failed         -> [ CRITICAL ]
# Stop_failed          -> [ CRITICAL ]
# Monitor_failed       -> [ CRITICAL ]
# Online_not_monitored -> [ WARNING ]
# Starting             -> [ WARNING ]
# Stopping             -> [ CRITICAL ]
# Not_online           -> [ CRITICAL ]
#

if (($opt_resources) or ($opt_all)){
        open (RESOURCES_STATUS, "$cluster_binary/clrs status |")
                or die "Couldn't execute program: $!";
        while (<RESOURCES_STATUS>){
                next unless /(Resource Name)/;
                my $match = $1;
                print "[$match]\n";
                my $line = <RESOURCES_STATUS>; # discard dashes
                while (!eof){
                        if ( ! (($line=<RESOURCES_STATUS>) =~ /^\s*$/) ){
                               print "read: $line";
                        }
                }

        }
        close(RESOURCES_STATUS);
}


### Subroutines

sub print_usage() {
	printf "\n";
	printf "usage: \n";
	printf "check_sun_cluster [-n] [-q] [-t] [-g] [-r] [-a] [-T=<timeout>] [-b] [-V] [-h]\n";
	printf "\n";
	exit $ERRORS{"UNKNOWN"};
}

sub print_help() {
	print "$PROGNAME v$VERSION";
	print_usage();
	printf "check_sun_cluster plugin for Nagios monitors the status \n";
	printf "of a Sun Cluster (version 3.2 or greater)\n";
	printf "\nUsage:\n";
	printf "   -n (--nodes)      check nodes are online\"\n";
	printf "   -q (--quorum)     check quorum\n";
	printf "   -t (--transport)  check transport paths\n";
	printf "   -g (--groups)     check resource groups\n";
	printf "   -r (--resources)  check resources\n";
	printf "   -a (--all)        check all\n";
	printf "   -T (--timeout)    seconds before the plugin times out (default=$TIMEOUT)\n";
	printf "   -b (--binary)     path where the cluster binaries are located\n";
	printf "                     (default = /usr/cluster/bin)\n";
	printf "   -V (--version)    Plugin version\n";
	printf "   -h (--help)       usage help \n\n";
	printf "Note: Either -n or -q or -t or -g or -r or -a must be specified.\n\n";
	
}

sub process_arguments() {
	Getopt::Long::config('bundling');
	$status = GetOptions(
			"V"   => \$opt_V,          "version"   => \$opt_V,
			"h"   => \$opt_h,          "help"      => \$opt_h,
			"n"   => \$opt_nodes,      "nodes"     => \$opt_nodes,
			"q"   => \$opt_quorum,     "quorum"    => \$opt_quorum,
			"t"   => \$opt_transport,  "transport" => \$opt_transport,
			"g"   => \$opt_groups,     "groups"    => \$opt_groups,
			"r"   => \$opt_resources,  "resources" => \$opt_resources,
			"a"   => \$opt_all,        "all"       => \$opt_all,
			"T:i" => \$timeout,        "timeout=i" => \$timeout,
			"b"   => \$cluster_binary, "binary"    => \$cluster_binary
			);


	if ($status == 0){
		print_help();
		exit $ERRORS{'UNKNOWN'};
	}

	if ($opt_V) {
		print "$PROGNAME v$VERSION";
		exit $ERRORS{'OK'};
	}

	if ($opt_h) {
		print_help();
		exit $ERRORS{'OK'};
	}

	unless ($opt_nodes || $opt_quorum || $opt_transport || $opt_groups 
                           || $opt_resources || $opt_all){
		print_help();
		exit $ERRORS{'OK'};	
	}

	unless (defined $timeout) {
		$timeout = $TIMEOUT;
	}

	unless (defined $cluster_binary){
		$cluster_binary = $BIN_PATH;
	}

}
## End validation

