#!/usr/bin/perl -w

# check_sun_cluster - Nagios plugin to check the status of a 
# Sun Cluster (version 3.2 or greater)

use strict;
use lib utils.pm;
use utils qw($TIMEOUT %ERRORS &support);
use Getopt::Long;
use vars qw($timeout $opt_V $opt_h $opt_nodes $opt_quorum $opt_transport $opt_groups $opt_resources $opt_all $cluster_binary);

my $PROGNAME = "check_sun_cluster";
my $VERSION = "1.0";
my $BIN_PATH = "/usr/cluster/bin";

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
my %groups_status_msg = ();
my %resources_status_msg = ();

my $num_options = 0; # Number of options executed

# MAIN

# Validate Arguments
my $status = process_arguments();

# Check nodes (option -n)
my $nodes_check = 0;
my $nodes_status = 0;
check_nodes() if (($opt_nodes) or ($opt_all));

# Check quorum (option -q)
my $quorum_check= 0;
my $quorum_status = 0;
check_quorum() if (($opt_quorum) or ($opt_all));

# Check transport paths (option -t)
my $transport_check = 0;
my $transport_status = 0;
check_transport_paths() if (($opt_transport) or ($opt_all));

# Check resource groups (option -g)
my $groups_check = 0;
my $groups_status = 0;
## Resources groups and Nagios status equivalences
my %groups_cluster_status = ( "Degraded" => "CRITICAL",
                              "Faulted"  => "CRITICAL",
                              "Offline"  => "CRITICAL",
                              "Online"   => "OK",
                              "Unknown"  => "WARNING"
                            );
check_resource_groups() if (($opt_groups) or ($opt_all));

# Check resources (option -r)
my $resources_check = 0;
my $resources_status = 0;
## Resources and Nagios status equialences
my %resources_cluster_status = ( "Online" => "OK",
                                 "Offline" => "CRITICAL",
                                 "Start_failed" => "CRITICAL",
                                 "Stop_failed" => "CRITICAL",
                                 "Monitor_failed" => "CRITICAL",
                                 "Online_not_monitored" => "WARNING",
                                 "Starting" => "WARNING",
                                 "Stopping" => "CRITICAL",
                                 "Not_online" => "CRITICAL"
                               );
check_resources() if (($opt_resources) or ($opt_all));

# Print cluster status and exit
print_cluster_status();
my $exit_status = cluster_status();
exit $ERRORS{"$exit_status"};

# SUBROUTINES

# Check nodes (option -n)
#
# Check the status of the cluster nodes (using the command 'clnode').
# Status check:
#    - Online  -> [ OK ]
#    - Offline -> [ CRITICAL ]

sub check_nodes {
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

sub check_quorum {
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
                (my $space, $votes_needed, $votes_present, $votes_possible) = split(/[ \t]+/, $line);
                chomp $votes_possible;
                next;
            };
            "Node Name" eq $match && do {
                while ( ! (($line=<QUORUM_STATUS>) =~ /^\s*$/) ){
                    my ($node, $present, $possible, $status) = split(/[ \t]+/, $line);
                    chomp $status;
                    my %node = ("name"=>$node, "present"=>$present,
                                "possible"=>$possible, "status"=>$status);
                    push @nodes, \%node;
                }
            };
            "Device Name" eq $match && do {
                while ( ! (($line=<QUORUM_STATUS>) =~ /^\s*$/) ){
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

# Check transport paths (option -t)
#
# Check the status of the interconnect paths.
#
# Transport status  Service status
# ----------------  --------------
#   Path online   -> [ OK ]
#   waiting       -> [ WARNING ]
#   faulted       -> [ CRITICAL ]

sub check_transport_paths {
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


# Check resource groups (option -g)
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

sub check_resource_groups {
    $num_options++;
    $groups_check = 1;
    # Run the command 'clrg status' and get a list
    # of the status of the cluster resource groups 
    open (GROUP_STATUS, "$cluster_binary/clrg status |")
        or die "Couldn't execute program: $!";
    # %groups = { "group_name" => [ %node1, %node2, ... ] }
    # %node1 = { "node_name" => x, "suspended" => y, "status" => z }
    my %groups = ();
    while (<GROUP_STATUS>){
        next unless /(Group Name)/;
        my $match = $1;
        my $line = <GROUP_STATUS>; # discard dashes
        my $group_name;
        while (!eof){
            $line = <GROUP_STATUS>;
            chomp $line;
            if ( $line =~ /^[^\s]/ ){
                # If the line starts with a non-space character => new group
                my ($node_name, $suspended, $status);
                ($group_name, $node_name, $suspended, $status) = split (/[ \t]+/, $line);
                my %node = ( "node_name"=>$node_name, "suspended"=>$suspended, "status"=>$status );
                my @nodes = ( \%node );
                $groups{$group_name} = \@nodes;
            } elsif ( ! $line =~ /^\s*$/ ) {
                # If the line is not blank => node belongs to the previous group
                my ($space, $node_name, $suspended, $status) = split(/[ \t]+/, $line);
                my %node = ( "node_name"=>$node_name, "suspended"=>$suspended, "status"=>$status );
                # TODO: if group_name is not defined => nagios UNKNOWN
                my @nodes = @{$groups{$group_name}};
                push @nodes, \%node;
                $groups{$group_name} = \@nodes;
            } else {
                # Blank line => End of group
            }
        }
    }
    close(GROUP_STATUS);

    # Check groups status from %groups and "calculate" groups status (and messages)
    foreach my $group_name ( keys %groups ){
        my $group_msg;
        my $group_status_str;
        my $nodes_msgs = "";
        my $msgs;
        my @nodes = @{$groups{$group_name}};
            # Get the group message: all the nodes messages
            foreach my $node ( @nodes ){
                $nodes_msgs = $nodes_msgs . "node:$node->{node_name} suspended:$node->{suspended} status:$node->{status} ";
            }
            # Get the status of the group (passed @nodes to the function).
            $group_status_str = get_status('groups', @nodes);
            # Set the group status message
            if ( ! exists $groups_status_msg{$group_status_str} ){
                $msgs = [];
            } else {
                $msgs = $groups_status_msg{$group_status_str};
            }
            $groups_status = $service_status_str{$group_status_str} if ( $service_status_str{$group_status_str} > $groups_status );
            push @$msgs, "group:$group_name ( ".$nodes_msgs.")";
            $groups_status_msg{$group_status_str} = $msgs;
        }
}

# Check resources (option -r)
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

sub check_resources {
    $num_options++;
    $resources_check = 1;
    # Run the command 'clrs status' and get a list
    # of the status of the cluster resources
    open (RESOURCES_STATUS, "$cluster_binary/clrs status |")
        or die "Couldn't execute program: $!";
    # %resources = { "resource_name" => [ %node1, %node2, ... ]
    # %node1 = { "node_name" => node_name, "status" => status }
    my %resources = ();
    while (<RESOURCES_STATUS>){
        next unless /(Resource Name)/;
        my $match = $1;
        my $line = <RESOURCES_STATUS>; # discard dashes
        my $resource_name;
        while (!eof){
            $line = <RESOURCES_STATUS>;
            chomp $line;
            if ( $line =~ /^[^\s]/ ){
                # If the line starts with a non-space character => new resource
                my ($node_name, $status, @status_msg);
                ($resource_name, $node_name, $status, @status_msg) = split (/[ \t]+/, $line);
                my $status_msg_str = join (" ", @status_msg);
                my %node = ( "node_name"=>$node_name, "status"=>$status, "status_msg"=>$status_msg_str );
                my @nodes = ( \%node );
                $resources{$resource_name} = \@nodes;
            } elsif ( ! $line =~ /^\s*$/ ) {
                # If the line is not blank => node belongs to the previous resources
                my ($space, $node_name, $status, @status_msg) = split(/[ \t]+/, $line);
                my $status_msg_str = join (" ", @status_msg);
                my %node = ( "node_name"=>$node_name, "status"=>$status, "status_msg"=>$status_msg_str );
                # TODO: if group_name is not defined => nagios UNKNOWN
                my @nodes = @{$resources{$resource_name}};
                push @nodes, \%node;
                $resources{$resource_name} = \@nodes;
            } else {
                # Blank line => End of resource
            }
        }
    }
    close(RESOURCES_STATUS);

    foreach my $resource_name ( keys %resources ){
        my $resource_msg;
        my $resource_status_str;
        my $nodes_msgs = "";
        my $msgs;
        my @nodes = @{$resources{$resource_name}};
        # Get the resource message: all the nodes messages
        foreach my $node ( @nodes ){
            $nodes_msgs = $nodes_msgs . "node:$node->{node_name} status:$node->{status} status_message:\"$node->{status_msg}\" ";
        }
        # Get the status of the resource (passed @nodes to the function).
        $resource_status_str = get_status('resources', @nodes);
        # Set the resource status message
        if ( ! exists $resources_status_msg{$resource_status_str} ){
            $msgs = [];
        } else {
            $msgs = $resources_status_msg{$resource_status_str};
        }
        $resources_status = $service_status_str{$resource_status_str} if ( $service_status_str{$resource_status_str} > $resources_status );
        push @$msgs, "resource:$resource_name ( ".$nodes_msgs.")";
        $resources_status_msg{$resource_status_str} = $msgs;
        }
}

sub get_status {
    my $option = shift; # groups OR resources
    my @nodes = shift;

    my $status_ok = 0;
    my $status_str;
    # If at least one node is Online -> OK
    # If not -> the status will be the "worse" one.
    foreach my $node ( @nodes ){
        my $node_status_str;
        if ( $option eq "groups" ){
            $node_status_str = $groups_cluster_status{$node->{status}};
        } elsif ( $option eq "resources" ) {
            $node_status_str = $resources_cluster_status{$node->{status}};
        } else {
            print "UNKNOWN - option must be 'groups' or 'resources'\n";
            exit $ERRORS{"UNKNOWN"};
        }
        if ($node_status_str eq "OK"){
            $status_ok = 1;
            $status_str = $node_status_str;
            last;
        } else {
            if ( ! defined($status_str) ) {
                $status_str = $node_status_str;
            } elsif ( $service_status_str{$status_str} < $service_status_str{$node_status_str} )  {
                $status_str = $node_status_str;
            }
        }
    }

    if ( $status_ok ) {
        return "OK";
    } else {
        return $status_str;
    }
}

sub cluster_status {
    my $cluster_status = 0;

    $cluster_status = $nodes_status if ( $nodes_status > $cluster_status );
    $cluster_status = $quorum_status if ( $quorum_status > $cluster_status );
    $cluster_status = $transport_status if ( $transport_status > $cluster_status );
    $cluster_status = $groups_status if ( $groups_status > $cluster_status );
    $cluster_status = $resources_status if ( $resources_status > $cluster_status );

    return $service_status{$cluster_status};
}

sub get_msgs {
    my $status_msgs = shift;
    my $msg = "";

    # Return only UNKNOWN, CRITICAL and WARNING messages
    foreach ( ("UNKNOWN", "CRITICAL", "WARNING") ){
        if ( exists $status_msgs->{$_} ) {
            my $msgs = $status_msgs->{$_};
            foreach ( @$msgs ){
                $msg = $msg . $_ . ". ";
            }
        }
    }

    return $msg;
}

sub print_cluster_status {
    my $nagios_msg = "";
    $nagios_msg = cluster_status() . " - ";

    my %cluster_status_msgs = ( "OK" => "",
                                "WARNING" => "",
                                "CRITICAL" => "",
                                "UNKNOWN" => "" );

    # print nodes status
    if ( $nodes_check == 1 ) {
            my $nodes_status_str = $service_status{$nodes_status};
            my $msg = $cluster_status_msgs{$nodes_status_str};
            $msg = $msg . "[NODES $nodes_status_str]: ";
            $msg = $msg . get_msgs ( \%nodes_status_msg );
            $cluster_status_msgs{$nodes_status_str} = $msg;
    }

    # print quorum status
    if ( $quorum_check == 1 ) {
        my $quorum_status_str = $service_status{$quorum_status};
        my $msg = $cluster_status_msgs{$quorum_status_str};
        $msg = $msg . "[QUORUM $service_status{$quorum_status}]: ";
        $msg = $msg . get_msgs ( \%quorum_status_msg );
        $cluster_status_msgs{$quorum_status_str} = $msg;
    }

    # print transport status
    if ( $transport_check == 1 ) {
        my $transport_status_str = $service_status{$transport_status};
        my $msg = $cluster_status_msgs{$transport_status_str};
        $msg = $msg . "[TRANSPORT $service_status{$transport_status}]: ";
        $msg = $msg . get_msgs ( \%transport_status_msg );
        $cluster_status_msgs{$transport_status_str} = $msg;
    }

    # print groups status
    if ( $groups_check == 1 ) {
        my $groups_status_str = $service_status{$groups_status};
        my $msg = $cluster_status_msgs{$groups_status_str};
        $msg = $msg . "[GROUPS $service_status{$groups_status}]: ";
        $msg = $msg . get_msgs ( \%groups_status_msg );
        $cluster_status_msgs{$groups_status_str} = $msg;
    }

    # print resources status
    if ( $resources_check == 1 ) {
        my $resources_status_str = $service_status{$resources_status};
        my $msg = $cluster_status_msgs{$resources_status_str};
        $msg = $msg . "[RESOURCES $service_status{$resources_status}]: ";
        $msg = $msg . get_msgs ( \%resources_status_msg );
        $cluster_status_msgs{$resources_status_str} = $msg;
    }

    # print nagios message
    print "$nagios_msg";
    foreach ( ("UNKNOWN", "CRITICAL", "WARNING", "OK") ){
        if ( exists $cluster_status_msgs{$_} ){
            print $cluster_status_msgs{$_};
        }
    }

    print "\n";
}

sub print_usage {
    printf "\n";
    printf "usage: \n";
    printf "check_sun_cluster [-n] [-q] [-t] [-g] [-r] [-a] [-T=<timeout>] [-b] [-V] [-h]\n";
    printf "\n";
    exit $ERRORS{"UNKNOWN"};
}

sub print_help {
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

sub process_arguments {
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

