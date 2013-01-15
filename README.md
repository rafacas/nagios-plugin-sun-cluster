# Nagios Sun Cluster Plugin

## Overview

Nagios plugin to check the status of a Sun Cluster for Solaris (version 3.2 or greater).

The 3.2 release of Solaris Cluster introduced an all-new Command Line Interface for managing the cluster. These are the equivalences between the previous and the new commands used to get the cluster status:

<pre><code>+------------------+-----------------+-------------------------+
|                  | Sun Cluster 3.1 |     Sun Cluster 3.2     |
+------------------+-----------------+-------------------------+
| Nodes            | scstat –n       | clnode status           |
| Quorum           | scstat –q       | clqorum status          |
| Transport info   | scstat –W       | clinterconnect status   |
| Resources        | scstat –g       | clresource status       |
| Resource Groups  | scstat -g       | clresourcegroup status  |
+------------------+-----------------+-------------------------+
</code></pre>

## Installation

In your Nagios plugins directory (in one of the nodes of the Sun Cluster) run:

<pre><code>git clone git://github.com/rafacas/nagios-plugin-sun-cluster.git</code></pre>

## Usage

### Install in Nagios

Edit your commands.cfg in your Nagios server and add the following (we are using NRPE to connect to the nodes):

<pre><code>define command {
    command_name    check_nrpe
    command_line    $USER1$/check_nrpe -H $HOSTADDRESS$ -c $ARG1$
}
</code></pre>

#### Check Nodes

The plugin uses the command <code>clnode status</code> to get the node status:
<pre><code>$clnode status

Cluster Nodes ===

--- Node Status ---

Node Name                             Status
---------                             ------
vincent                               Online
theo                                  Online
</code></pre>

The following are the possible states of a node:
<pre><code>+-------------+---------------+
| Node status | Nagios status |
+-------------+---------------+
| Online      | OK            |
| Offline     | CRITICAL      |
+-------------+---------------+
</code></pre>

services.cfg file:
<pre><code>define service {
    use                     generic-service
    hostgroup_name          Sun Cluster
    service_description     Sun Cluster Nodes
    check_command           check_nrpe!check_sun_cluster_nodes
}
</code></pre>

nrpe.cfg file:
<pre><code>command[check_sun_cluster_nodes]=/usr/local/nagios/libexec/check_sun_cluster.pl -n</code></pre>

#### Check Quorum

The plugin uses the command <code>clquorum status</code> to get the quorum device status:
<pre><code># clq status

Cluster Quorum ===

--- Quorum Votes Summary ---

             Needed   Present   Possible
             ------   -------   --------
             2        3         3


--- Quorum Votes by Node ---

Node Name        Present       Possible       Status
---------        -------       --------       ------
vincent          1             1              Online
theo             1             1              Online

The following are the possible states of a node:
<pre><code>+----------------+---------------+
| Quorum status  | Nagios status |
+----------------+---------------+
| Online         | OK            |
| Offline        | CRITICAL      |
+----------------+---------------+
</code></pre>

services.cfg file:
<pre><code>define service {
    use                     generic-service
    hostgroup_name          Sun Cluster
    service_description     Sun Cluster Nodes
    check_command           check_nrpe!check_sun_cluster_quorum
}
</code></pre>

nrpe.cfg file:
<pre><code>command[check_sun_cluster_quorum]=/usr/local/nagios/libexec/check_sun_cluster.pl -q</code></pre>
--- Quorum Votes by Device ---

Device Name        Present         Possible         Status
-----------        -------         --------         ------
d4                 1               1                Online
</code></pre>


