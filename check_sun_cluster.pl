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

# Nagios service status: OK < WARNING < CRITICAL < UNKNOWN
my %service_status_str = ( "OK"       => 0,
                           "WARNING"  => 1,
                           "CRITICAL" => 2,
                           "UNKNOWN"  => 3
                         );
my %service_status = ( 0 => "OK",
                       1 => "WARNING",
                       2 => "CRITICAL",
                       3 => "UNKNOWN"
                     );

# Messages to return to Nagios
# status_msg { "OK" => [ ok_msgs ],
#              "WARNING" => [ warning_msgs ],
#              "CRITICAL" => [ critical_msgs ],
#              "UNKNOWN" => [ unknown_msgs ]
#            }
my %nodes_status_msg = ();
my %quorum_status_msg = ();
my %transport_status_msg = ();
my %groups_status = ();
my %resources_status = ();

# Number of options executed
my $num_options = 0; 

# Check nodes (option -n)
#
# Check the status of the cluster nodes (using the command 'clnode').
# Status check:
#    - Online  -> [ OK ]
#    - Offline -> [ CRITICAL ]

my $nodes_check = 0;
my $nodes_status = 0;
if (($opt_nodes) or ($opt_all)){
        $num_options++;
        $nodes_check = 1;

        # Nodes and Nagios status equivalences
        my %nodes_cluster_status = ( "Online"  => "OK",
                                     "Offline" => "CRITICAL"
                                   );

	# Run the command 'clnode status' and get a list
	# of nodes and their status
        my @nodes;
        open (NODE_STATUS, "$cluster_binary/clnode status |")
                or die "Couldn't execute program: $!";
        while (<NODE_STATUS>){
                next unless /(Node Name)/;
                my $match = $1;
                my $line = <NODE_STATUS>; # discard dashes
                while (!eof){
                        if ( !(($line=<NODE_STATUS>) =~ /^\s*$/) ){
				print "read: $line";
                                my ($node, $status) = split(/[ \t]+/, $line);
                                chomp $status;
                                my %node = ("name"=>$node, "status"=>$status);
                                push @nodes, \%node;
                        }
                }
        }
        close (NODE_STATUS);

	# Generate the Nagios node status depending on the status at @nodes
	# Add the status messages to %nodes_status_msg
        foreach (@nodes){
                my $msg = "$_->{name} $_->{status}";
                my $msgs;
                my $node_status_str = $nodes_cluster_status{$_->{status}};
                if ( ! exists $nodes_status_msg{$node_status_str} ){
                        $msgs = [];
                } else {
                        $msgs = $nodes_status_msg{$nodes_cluster_status{$_->{status}}};
                }
                $nodes_status = $service_status_str{$node_status_str} if ( $service_status_str{$node_status_str} > $nodes_status );
                push @$msgs, $msg;
                $nodes_status_msg{$nodes_cluster_status{$_->{status}}} = $msgs;
        }

}

# Check quorum (option -q)
#
# Check the status and vote counts of quorum devices (using the commnad 'clquorum').
# Node status  Service status
# -----------  -------------
#   Online   -> [ OK ]
#   Offline  -> [ CRITICAL ]
#
# Votes are not checked

my $quorum_check= 0;
my $quorum_status = 0;
if (($opt_quorum) or ($opt_all)){
        $num_options++;
        $quorum_check = 1;
        # Quorum and Nagios status equivalences
        my %quorum_cluster_status = ( "Online"  => "OK",
                                      "Offline" => "CRITICAL"
                                    );
        my ($votes_needed, $votes_present, $votes_possible);
        my @nodes;
        my @devices;

	# Run the command 'clquorum status' and get a list
        # of votes, nodes and devices with their status
        open (QUORUM_STATUS, "$cluster_binary/clquorum status |")
                or die "Couldn't execute program: $!";
        while (<QUORUM_STATUS>){
                next unless /((Needed)|(Node Name)|(Device Name))/;
                my $match = $1;
                my $line = <QUORUM_STATUS>; # discard dashes

                # useless label to remark that this is a case statement in disguise
                CASES:
                "Needed" eq $match && do {
                        $line=<QUORUM_STATUS>;
                        print "read: $line";
                        (my $space, $votes_needed, $votes_present, $votes_possible) = split(/[ \t]+/, $line);
                        chomp $votes_possible;
                        next;
                };
                "Node Name" eq $match && do {
                        while ( ! (($line=<QUORUM_STATUS>) =~ /^\s*$/) ){
                                print "read: $line";
                                my ($node, $present, $possible, $status) = split(/[ \t]+/, $line);
                                chomp $status;
                                my %node = ("name"=>$node, "present"=>$present,
                                            "possible"=>$possible, "status"=>$status);
                                push @nodes, \%node;
                        }
                };
		"Device Name" eq $match && do {
                        while ( ! (($line=<QUORUM_STATUS>) =~ /^\s*$/) ){
                                print "read: $line";
                                my ($device, $present, $possible, $status) = split(/[ \t]+/, $line);
                                chomp $status;
                                my %device = ("name"=>$device, "present"=>$present,
                                              "possible"=>$possible, "status"=>$status);
                                push @devices, \%device;
                        }
                };
        }
        close(QUORUM_STATUS);

        # Check quorum votes summary
        # NOTE: No votes checking for now
        my $msgs;
        my $msg = "votes needed:$votes_needed votes present:$votes_present votes possible:$votes_possible";
        if ( ! exists $quorum_status_msg{"OK"}){
                $msgs = [];
        } else {
                $msgs = $quorum_status_msg{"OK"};
        }
        push @$msgs, $msg;
        $quorum_status_msg{"OK"} = $msgs;

        # Check quorum by node and by device
        foreach ( (@nodes, @devices) ) {
                my $msg = "$_->{name} $_->{status}";
                my $msgs;
                my $quorum_status_str = $quorum_cluster_status{$_->{status}};
                if ( ! exists $quorum_status_msg{$quorum_status_str} ){
                        $msgs = [];
                } else {
                        $msgs = $quorum_status_msg{$quorum_cluster_status{$_->{status}}};
                }
                $quorum_status = $service_status_str{$quorum_status_str} if ( $service_status_str{$quorum_status_str} > $quorum_status );
                push @$msgs, $msg;
                $quorum_status_msg{$quorum_cluster_status{$_->{status}}} = $msgs;
        }
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

my $transport_check = 0;
my $transport_status = 0;
if (($opt_transport) or ($opt_all)){
        $num_options++;
        $transport_check = 1;
	# Transport and Nagios status equivalences
        my %transport_cluster_status = ( "Path online" => "OK",
                                         "waiting"     => "WARNING",
                                         "faulted"     => "CRITICAL"
                                      );
	# Run the command 'clntr status' and get a list
        # of the status of the transport paths
        my @paths;
        open (TRANSPORT_STATUS, "$cluster_binary/clintr status |")
                or die "Couldn't execute program: $!";
        while (<TRANSPORT_STATUS>){
                next unless /(Endpoint)/;
                my $match = $1;
                my $line = <TRANSPORT_STATUS>; # discard dashes
                while (!eof){
                        if ( ! (($line=<TRANSPORT_STATUS>) =~ /^\s*$/) ){
				print "read: $line";
                                my ($endpoint1, $endpoint2, @status) = split(/[ \t]+/, $line);
                                my $status_str = join (" ", @status);
                                chomp $status_str;
                                my %path = ("endpoint1"=>$endpoint1, "endpoint2"=>$endpoint2, "status"=>$status_str);
                                push @paths, \%path;

                        }
                }
        }
        close(TRANSPORT_STATUS);

        # Check path status and "calculate" the service status and messages
        foreach (@paths){
                my $msg = "$_->{endpoint1}-$_->{endpoint2} $_->{status}";
                my $msgs;
                my $path_status_str = $transport_cluster_status{$_->{status}};
                if ( ! exists $transport_status_msg{$path_status_str} ){
                        $msgs = [];
                } else {
                        $msgs = $transport_status_msg{$transport_cluster_status{$_->{status}}};
                }
                $transport_status = $service_status_str{$path_status_str} if ( $service_status_str{$path_status_str} > $transport_status );
                push @$msgs, $msg;
                $transport_status_msg{$transport_cluster_status{$_->{status}}} = $msgs;
        }

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

