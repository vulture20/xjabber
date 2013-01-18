#!/usr/bin/perl -w
# xjabber.pl - Mainscript of the XJabber-Server
# Copyright (C)2012-2013 Thorsten Schroepel. All right reserved
#
# If you make any modifications or improvements to the code, I would
# appreciate that you share the code with me so that I might include
# it in the next release. I can be contacted through
# http://www.schroepel.net/.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#############################################################

use strict;
use YAML;
use DBI;
use Net::XMPP;
use Net::Jabber;
use Device::SerialPort;
use Device::XBee::API;
use Digest::SHA qw(hmac_sha256_hex);
use Time::HiRes qw(setitimer ITIMER_VIRTUAL time);

#############################################################

my $config = YAML::LoadFile("/etc/xjabber/xjabber.conf");

#############################################################

$SIG{HUP} = \&Stop;
$SIG{KILL} = \&Stop;
$SIG{TERM} = \&Stop;
$SIG{INT} = \&Stop;

my $oldtime = 0;

my $serial_port_device = Device::SerialPort->new($config->{xbeedev}) || die $!;
$serial_port_device->baudrate($config->{xbeebaud});
$serial_port_device->databits($config->{xbeedatabits});
$serial_port_device->stopbits($config->{xbeestopbits});
$serial_port_device->parity($config->{xbeeparity});
$serial_port_device->read_char_time(0);
$serial_port_device->read_const_time(1000);

my $xbee = Device::XBee::API->new({fh => $serial_port_device, packet_timeout => 3, api_mode_escape => 2}) || die $!;
#my $xbee = Device::XBee::API->new({fh => $serial_port_device, api_mode_escape => 2}) || die $!;
debug("XBee->Discover()...\n");
$xbee->discover_network();

debug("DBI->connect()...\n");
my $dbh = DBI->connect("DBI:mysql:".$config->{mysqldb}, $config->{mysqluser}, $config->{mysqlpassword});

my $connection = new Net::XMPP::Client();
$connection->SetCallBacks(message=>\&InMessage);
my $status = $connection->Connect(
    hostname => $config->{hostname}, port => $config->{port},
    componentname => $config->{componentname},
    connectiontype => $config->{connectiontype}, tls => $config->{tls});

if (!(defined($status))) {
    print "ERROR: XMPP connection failed.\n";
    print "		($!)\n";
    exit(0);
}

my $sid = $connection->{SESSION}->{id};
$connection->{STREAM}->{SIDS}->{$sid}->{hostname} = $config->{componentname};

my @result = $connection->AuthSend(
    username => $config->{username}, password => $config->{password},
    resource => $config->{resource});

if ($result[0] ne "ok") {
    print "ERROR: Authorization failed: $result[0] - $result[1]\n";
    exit(0);
}

debug("XBee->PresenceSend()...\n");
$connection->PresenceSend();

while (1) {
    # Process incoming Jabber-Messages
    if (!defined($connection->Process(1))) {
	debug("XBee->Disconnected()\n");
	exit(254);
    }
    # Interval-Timer
    if ($oldtime < time) {
	$oldtime = time + $config->{interval};
	debug("Main->Interval()\n");
	sendGTasks($config->{xbeedisplay});
	sendTS3User($config->{xbeedisplay});
	sendWeather($config->{xbeedisplay});
    }
    # Process incoming XBee-Messages
    if (my $rx = $xbee->rx()) {
	if (($rx->{api_type} eq Device::XBee::API->XBEE_API_TYPE__ZIGBEE_RECEIVE_PACKET)) {
	
	    my $ni = $xbee->{known_nodes}->{$rx->{sh} . "_" . $rx->{sl}}->{ni};
	    if (!defined($ni)) { $ni = "N/A"; }
	
	    my $body = sprintf("%x:%x (%s)> %s", $rx->{sh}, $rx->{sl}, $ni, $rx->{data});
	    debug("XBee->MessageSend(".$config->{sendTo}.")->$body\n");
	    debug("Xbee->MessageSend(".$config->{sendTo}.")->Hash(" . hmac_sha256_hex($body, $config->{hmacKey}) . ")\n");
	    $connection->MessageSend(
		to => $config->{sendTo}."\@".$config->{componentname}, body => $body,
		resource => $config->{resource});

	    if (($rx->{data} =~ m/C([0-9]*)/i) && (lc($ni) eq $config->{xbeedoor})) {
		my $hash = hmac_sha256_hex($1, $config->{hmacKey});
		my $body = sprintf("%x:%x (%s)> %s", $rx->{sh}, $rx->{sl}, $ni, "H$hash");
		$connection->MessageSend(
		    to => $config->{sendTo}."\@".$config->{componentname}, body => $body,
		    resource => $config->{resource});
		if (!$xbee->tx({sh => $rx->{sh}, sl => $rx->{sl}}, "H$hash")) {
		    print "XBee->Transmit(H...) failed!\n";
		}
	    } elsif (($rx->{data} =~ m/R([0-9a-zA-Z]*)/i) && (lc($ni) eq $config->{xbeedoor})) {
		my $body = sprintf("%x:%x (%s)> RFID = %s", $rx->{sh}, $rx->{sl}, $ni, $1);
		debug("XBee->RFID($1)\n");
		$connection->MessageSend(
		    to => $config->{sendTo}."\@".$config->{componentname}, body => $body,
		    resource => $config->{resource});
	    }
	}
    }
}

exit(0);

# Deconstructor - Clean everything up before exiting
# Parameter: none
# Returns: nothing
sub Stop {
    debug("Main->Exit()\n");
    $dbh->disconnect();
    $connection->Disconnect();
    exit(0);
}

# A Jabber-Message was received and should be handled
# Parameter: sid, message
# Returns: nothing
sub InMessage {
    my $sid = shift;
    my $message = shift;

    my $type = $message->GetType();
    my $fromJID = $message->GetFrom("jid");

    my $from = $fromJID->GetUserID();
    my $resource = $fromJID->GetResource();
    my $server = $fromJID->GetServer();
    my $subject = $message->GetSubject();
    my $body = $message->GetBody();

    # Leere Nachricht
    # wird anscheinend oft als Benachrichtigung, dass das Gegenüber schreibt verwendet
    if ($body eq "") { return; }

    # discover
    # Veranlasse ein Discover des XBee-Moduls
    if ($body =~ m/^discover/i) {
	debug("XBee->Discover()...\n");
	$connection->MessageSend(
	    to => "$from\@$server", body => "Discovering...",
    	    resource => $resource);
	$xbee->discover_network();
    # exit
    # Beende den Server
    } elsif ($body =~ m/^exit/i) {
	debug("Main->Exit()\n");
	$connection->Disconnect();
	exit(0);
    # nodes
    # Gebe die bekannten Nodes aus
    } elsif ($body =~ m/^nodes/i) {
	$connection->MessageSend(
	    to => "$from\@$server", body => "Known Nodes:",
	    resource => $resource);
	while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	    my $tmp = sprintf("%x_%x (%s): %x", $v->{sh}, $v->{sl}, $v->{ni}, $v->{na});
	    $connection->MessageSend(
		to => "$from\@$server", body => $tmp,
		resource => $resource);
	}
    # send testnode message
    # Sende an Node mit dem angegebenen Namen
    } elsif ($body =~ m/^send ([a-zA-Z0-9]*) (.*)/i) {
	debug("XBee->Send($1 => $2)\n");
	my $found = 0;
	my $sh = 0; my $sl = 0;
	while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	    if (lc($v->{ni}) eq lc($1)) {
		$sh = $v->{sh};
		$sl = $v->{sl};
		$found = 1;
	    }
	}
	if ($found == 1) {
	    if (!$xbee->tx({sh => $sh, sl => $sl}, $2)) {
		printf("XBee->Transmit(%x, %x, %s) failed!\n", $sh, $sl, $2);
	    }
	} else {
	    debug("XBee->Send($1) Node not found!\n");
	    $connection->MessageSend(
		to => "$from\@$server", body => "XBee->Send($1) Node not found!",
		resource => $resource);
	}
    # send 13a200_406fffff message
    # Sende an 64bit-Adresse
    } elsif ($body =~ m/^send ([a-zA-Z0-9]*)_([a-zA-Z0-9]*) (.*)/i) {
	debug("XBee->Send($1_$2 => $3)\n");
        if (!$xbee->tx({sh => hex($1), sl => hex($2)}, $3)) {
            print "XBee->Transmit($1_$2) failed!\n";
        }
    # broadcast message
    # Sende Nachricht per Broadcast
    } elsif ($body =~ m/^broadcast (.*)/i) {
	debug("XBee->Broadcast($1)\n");
	if (!$xbee->tx($1)) {
	    print "XBee->Transmit($1) failed!\n";
	}
    # open door 1
    # Öffnet Tür (1=Wohnungstür, 2=Haustür, 3=beide Türen)
    } elsif ($body =~ m/^open door ([1-3])/i) {
	debug("XBee->Open_Door($1)\n");
	my $found = 0;
	my $sh = 0; my $sl = 0;
	while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	    if (lc($v->{ni}) eq $config->{xbeedoor}) {
		$sh = $v->{sh};
		$sl = $v->{sl};
		$found = 1;
	    }
	}
	if ($found == 1) {
	    if (!$xbee->tx({sh => $sh, sl => $sl}, "R$1")) {
		printf("XBee->Transmit(%x, %x, R%s) failed!\n", $sh, $sl, $1);
	    }
	} else {
	    debug("XBee->Send($1) Node not found!\n");
	    $connection->MessageSend(
		to => "$from\@$server", body => "XBee->Send($1) Node not found!",
		resource => $resource);
	}
    # Kein Befehl - ignorieren bzw. debuggen
    } else {
	if ($config->{debug}) {
	    print "===\n";
	    print "Message ($type)\n";
	    print "  From: $from ($resource)\n";
	    print "  Subject: $subject\n";
	    print "  Body: $body\n";
	    print "  Hash: " . hmac_sha256_hex($body, $config->{hmacKey});
	    print "===\n";
	    print $message->GetXML(),"\n";
	    print "===\n";
	}
    }
}

# Prints the given message if debugging is enabled
# Parameter: the messagestring
# Returns: nothing
sub debug {
    if ($config->{debug}) { print shift; }
    return;
}

# Reads the next 3 tasks from the db and sends its content to the display-node
# Parameter: name of the destination-node
# Returns: nothing
sub sendGTasks {
    my $node = shift;

    my $found = 0;
    my $sh = 0; my $sl = 0;
    while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	if (lc($v->{ni}) eq $node) {
	    $sh = $v->{sh};
	    $sl = $v->{sl};
	    $found = 1;
	}
    }
    if ($found == 1) {
	my $i = 0;
	my ($task, $period);

	my $query = qq{ SELECT task, period FROM gcalendar ORDER BY id ASC LIMIT 3; };
	my $sth = $dbh->prepare($query);
	$sth->execute();
	$sth->bind_columns(undef, \$task, \$period);
	while ($sth->fetch()) {
	    if (!$xbee->tx({sh => $sh, sl => $sl}, "G$i$task|$period")) {
		print "XBee->Transmit($node) failed!\n";
	    }
	    debug("XBee()->Display(G$i$task|$period)\n");
	    $i++;
	}
    } else {
	debug("XBee->Send($node) Node not found!\n");
    }
}

# Reads the logged in TS3-clients from the db and sends the content to
#   the display-node
# Parameter: name of the destination-node
# Returns: nothing
sub sendTS3User {
    my $node = shift;

    my $found = 0;
    my $sh = 0; my $sl = 0;
    while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	if (lc($v->{ni}) eq $node) {
	    $sh = $v->{sh};
	    $sl = $v->{sl};
	    $found = 1;
	}
    }
    if ($found == 1) {
	my $i = 0;
	my $client_nickname;

	my $query = qq{ SELECT client_nickname FROM teamspeak; };

	my $sth = $dbh->prepare($query);
	$sth->execute();
	$sth->bind_columns(undef, \$client_nickname);
	while ($sth->fetch()) {
	    if (!$xbee->tx({sh => $sh, sl => $sl}, "T$i$client_nickname")) {
		print "XBee->Transmit($node) failed!\n";
	    }
	    debug("XBee()->Display($sh, $sl, T$i$client_nickname)\n");
	    $i++;
	}
    } else {
	debug("XBee->Send($node) Node not found!\n");
    }
}

# Reads weather data from the db and sends the content to the display-node
# Parameter: name of the destination-node
# Returns: nothing
sub sendWeather {
    my $node = shift;

    my $found = 0;
    my $sh = 0; my $sl = 0;
    while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	if (lc($v->{ni}) eq $node) {
	    $sh = $v->{sh};
	    $sl = $v->{sl};
	    $found = 1;
	}
    }
    if ($found == 0) {
	my ($condition_timecode, $condition_code, $condition_temp, $conditionString);
	my ($forecast_timecode, $forecast_low, $forecast_high, $forecast_code);
	my $dateformat = $config->{dateformat};

	querydb("SELECT DATE_FORMAT(timecode, '$dateformat'), code, temp FROM weather_condition ORDER BY id DESC LIMIT 1;", undef, \$condition_timecode, \$condition_code, \$condition_temp);
	$conditionString = getCondString($condition_code);

	if (!$xbee->tx({sh => $sh, sl => $sl}, "W0$condition_timecode|$condition_temp|$condition_code|$conditionString")) {
	    print "XBee->Transmit($node) failed!\n";
	}
	debug("XBee()->Display($sh, $sl, W0$condition_timecode|$condition_temp|$condition_code|$conditionString)\n");

	my $sth = querydb("SELECT DATE_FORMAT(timecode, '%w'), low, high, code FROM weather_forecast ORDER BY id DESC LIMIT 2;", undef, \$forecast_timecode, \$forecast_low, \$forecast_high, \$forecast_code);
	for (my $i=1; $i<=$sth->rows; $i++) {
	    $conditionString = getCondString($forecast_code);
	    my $weekday = @{$config->{weekdays}}[$forecast_timecode];
	    if (!$xbee->tx({sh => $sh, sl => $sl}, "W$i$weekday|$forecast_low|$forecast_high|$forecast_code|$conditionString")) {
		print "XBee->Transmit($node) failed!\n";
	    }
	    debug("XBee()->Display($sh, $sl, W$i$weekday|$forecast_low|$forecast_high|$forecast_code|$conditionString)\n");
	    if ($i < 2) { $sth->fetch(); }
	}
    } else {
	debug("XBee->Send($node) Node not found!\n");
    }
}

# Resolves the XBee-Deviceaddress from its name
# Parameter: Devicename
# Returns: Deviceobject or undef
sub resolveName {
    my $name = shift;
    my $sh = 0; my $sl = 0;
    while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	if (lc($v->{ni}) eq $config->{$name}) {
	    $sh = $v->{sh};
	    $sl = $v->{sl};
	    return $v;
	}
    }
    return undef;
}

# Resolves the XBee-Devicename from its address
# Parameter: sh, sl
# Returns: Devicename or undef
sub resolveID {
    my ($sh, $sl) = @_;
    while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	if (($sh eq $v->{sh}) && ($sl eq $v->{sl})) {
	    return $v->{ni};
	}
    }
    return undef;
}

# Wrapper to query the db and fetch the results
# Parameter: query, var1, var2 ... varx
# Returns: Handle $sth (Results in var1 ... varx)
sub querydb {
    my $query = shift;

    my $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->bind_columns(@_);
    $sth->fetch();
    return $sth;
}

# Queries the Conditionstring for an given id
# Parameter: id
# Returns: ConditionString or undef
sub getCondString {
    my $id = shift;
    my $condString;

    my $sth = querydb("SELECT conditionString FROM weather_condString WHERE id=$id;", undef, \$condString);
    if ($sth->rows == 0) { return undef; }
    return $condString;
}
