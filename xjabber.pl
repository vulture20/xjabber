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
use POSIX qw(strftime);

#############################################################

my $config = YAML::LoadFile("/etc/xjabber/xjabber.conf");

#############################################################

$SIG{HUP} = \&Stop;
$SIG{KILL} = \&Stop;
$SIG{TERM} = \&Stop;
$SIG{INT} = \&Stop;

my ($oldtime, $discovertime, $challengetime) = (0, time + $config->{discover}, 0);
my $rfidunknowntime = 0;

my $serial_port_device = Device::SerialPort->new($config->{xbeedev}) || die $!;
$serial_port_device->baudrate($config->{xbeebaud});
$serial_port_device->databits($config->{xbeedatabits});
$serial_port_device->stopbits($config->{xbeestopbits});
$serial_port_device->parity($config->{xbeeparity});
$serial_port_device->read_char_time(0);
$serial_port_device->read_const_time(1000);

my $xbee = Device::XBee::API->new({fh => $serial_port_device, packet_timeout => 3}) || die $!;
debug("XBee->Discover()...\n", 1);
$xbee->discover_network();

debug("DBI->connect()...\n", 1);
my $dbh = DBI->connect("DBI:mysql:".$config->{mysqldb}, $config->{mysqluser}, $config->{mysqlpassword}) || die $!;

my $connection = new Net::XMPP::Client();
$connection->SetCallBacks(message=>\&InMessage);
my $status = $connection->Connect(
    hostname => $config->{hostname}, port => $config->{port},
    componentname => $config->{componentname},
    connectiontype => $config->{connectiontype}, tls => $config->{tls});

if (!(defined($status))) {
    error("XMPP connection failed.\n		($!)\n");
    Stop(1);
}

my $sid = $connection->{SESSION}->{id};
$connection->{STREAM}->{SIDS}->{$sid}->{hostname} = $config->{componentname};

my @result = $connection->AuthSend(
    username => $config->{username}, password => $config->{password},
    resource => $config->{resource});

if ($result[0] ne "ok") {
    error("Authorization failed: $result[0] - $result[1]\n");
    Stop(2);
}

debug("XBee->PresenceSend()...\n", 2);
$connection->PresenceSend();

while (1) {
    # Process incoming Jabber-Messages
    if (!defined($connection->Process(1))) {
	debug("XBee->Disconnected()\n", 1);
	Stop(254);
    }
    # Interval-Timer
    if ($oldtime < time) {
	$oldtime = time + $config->{interval};
	debug("Main->Interval()\n", 2);
	sendGTasks($config->{xbeedisplay});
	sendTS3User($config->{xbeedisplay});
	sendWeather($config->{xbeedisplay});
    }
    if ($discovertime < time) {
	$discovertime = time + $config->{discover};
	debug("Main->Discoverinterval()\n", 2);
	$xbee->discover_network();
    }
    # Process incoming XBee-Messages
    if (my $rx = $xbee->rx()) {
	if (($rx->{api_type} eq Device::XBee::API->XBEE_API_TYPE__ZIGBEE_RECEIVE_PACKET)) {
	
	    my $ni = $xbee->{known_nodes}->{$rx->{sh} . "_" . $rx->{sl}}->{ni};
	    if (!defined($ni)) { $ni = "N/A"; }
	
	    my $body = sprintf("%x:%x (%s)> %s", $rx->{sh}, $rx->{sl}, $ni, $rx->{data});
	    debug("XBee->MessageSend(".$config->{sendTo}.")->$body\n", 4);
	    debug("XBee->MessageSend(".$config->{sendTo}.")->Hash(" . hmac_sha256_hex($body, $config->{hmacKey}) . ")\n", 4);
	    $connection->MessageSend(
		to => $config->{sendTo}."\@".$config->{componentname}, body => $body,
		resource => $config->{resource});

	    if (($rx->{data} =~ m/C([0-9]*)/i) && (lc($ni) eq $config->{xbeedoor})) {
		debug("XBee->Challenge($1)\n", 4);
		debug("Challengetime: $challengetime - Time: " . time . " - Diff: " . ($challengetime - time) . "\n", 5);
		if ($challengetime > time) {
		    my $hash = hmac_sha256_hex($1, pack("H*", $config->{hmacKey}));
		    my $body = sprintf("%x:%x (%s)> %s", $rx->{sh}, $rx->{sl}, $ni, "H$hash");
		    $connection->MessageSend(
			to => $config->{sendTo}."\@".$config->{componentname}, body => $body,
			resource => $config->{resource});
		    if (!$xbee->tx({sh => $rx->{sh}, sl => $rx->{sl}}, "H$hash")) {
			error("XBee->Transmit(H...) failed!\n");
		    }
		} else {
		    error("Challenge has been timed out!\n");
		}
	    } elsif (($rx->{data} =~ m/R([0-9a-zA-Z]*)/i) && (lc($ni) eq $config->{xbeedoor})) {
		my ($rfid_id, $rfid_description, $rfid_lastseen, $rfid_validuntil, $rfid_valid);
		my $dateformat = $config->{dateformat};
		my $body = sprintf("%x:%x (%s)> RFID = %s", $rx->{sh}, $rx->{sl}, $ni, $1);
		debug("XBee->RFID($1)\n", 3);
		$connection->MessageSend(
		    to => $config->{sendTo}."\@".$config->{componentname}, body => $body,
		    resource => $config->{resource});

		my $sth = querydb("SELECT id, description, DATE_FORMAT(lastseen, '$dateformat'), DATE_FORMAT(validuntil, '$dateformat'), validuntil-now()>0 as valid FROM rfid WHERE tag='" . lc($1) . "'",
		    undef, \$rfid_id, \$rfid_description, \$rfid_lastseen, \$rfid_validuntil, \$rfid_valid);
		if ($sth->rows == 0) {
		    debug("Unknown RFID-Tag!\n", 3);
		    $rfidunknowntime = time + $config->{rfiddelay};
		    querydb("SELECT MAX(id) FROM rfid;", undef, \$rfid_id);
		    $rfid_id++;
		    my $query = qq{ INSERT INTO rfid (tag, description, lastseen, validuntil) VALUES ("$1", "Autoadded Tag #$rfid_id", NOW(), 0) };
		    $dbh->do($query);
		} else {
		    my $validstr = $rfid_valid ? "valid" : "INVALID";
		    if (!$rfid_valid) { $rfidunknowntime = time + $config->{rfiddelay}; }
		    debug("RFID-Tag #$rfid_id \"$rfid_description\" found and is $validstr.\n", 3);
		    if ($rfidunknowntime < time) {
			# later we will here open the door
		    } else {
			debug("RFID-Delay isn't over. (" . int($rfidunknowntime - time) . " secs to go...)\n", 3);
		    }
		}
		my $query = qq{ UPDATE rfid SET lastseen=NOW() WHERE id=$rfid_id LIMIT 1 };
		$dbh->do($query);
		$query = qq{ INSERT INTO rfid_log (tag_id) VALUES ($rfid_id) };
		$dbh->do($query);
	    }
	}
    }
}

Stop(253);

# Deconstructor - Clean everything up before exiting
# Parameter: none
# Returns: nothing
sub Stop {
    my $retval = 0;

    if ((defined $_[0]) && ($_[0] ne "INT")) { $retval = $_[0]; }
    debug("Main->Exit($retval)\n", 1);
    $dbh->disconnect();
    $connection->Disconnect();
    $serial_port_device->close();
    undef $serial_port_device;
    exit($retval);
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
	debug("XBee->Discover()...\n", 3);
	$connection->MessageSend(
	    to => "$from\@$server", body => "Discovering...",
    	    resource => $resource);
	$xbee->discover_network();
    # exit
    # Beende den Server
    } elsif ($body =~ m/^exit/i) {
	Stop(0);
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
	debug("XBee->Send($1 => $2)\n", 3);
	if (my $tmp = resolveName($1)) {
	    my $sh = $tmp->{sh}; my $sl = $tmp->{sl};

	    if (!$xbee->tx({sh => $sh, sl => $sl}, $2)) {
		my $tmp = sprintf("XBee->Transmit(%x, %x, %s) failed!\n", $sh, $sl, $2);
		error($tmp);
	    }
	} else {
	    debug("XBee->Send($1) Node not found!\n", 3);
	    $connection->MessageSend(
		to => "$from\@$server", body => "XBee->Send($1) Node not found!",
		resource => $resource);
	}
    # send 13a200_406fffff message
    # Sende an 64bit-Adresse
    } elsif ($body =~ m/^send ([a-zA-Z0-9]*)_([a-zA-Z0-9]*) (.*)/i) {
	debug("XBee->Send($1_$2 => $3)\n", 3);
        if (!$xbee->tx({sh => hex($1), sl => hex($2)}, $3)) {
            error("XBee->Transmit($1_$2) failed!\n");
        }
    # broadcast message
    # Sende Nachricht per Broadcast
    } elsif ($body =~ m/^broadcast (.*)/i) {
	debug("XBee->Broadcast($1)\n", 3);
	if (!$xbee->tx($1)) {
	    error("XBee->Transmit($1) failed!\n");
	}
    # open door 1
    # Öffnet Tür (1=Wohnungstür, 2=Haustür, 3=beide Türen)
    } elsif ($body =~ m/^open door ([1-3])/i) {
	debug("XBee->Open_Door($1)\n", 3);
	if (my $tmp = resolveName($config->{xbeedoor})) {
	    my $sh = $tmp->{sh}; my $sl = $tmp->{sl};

	    $challengetime = time + $config->{challengeinterval};
	    if (!$xbee->tx({sh => $sh, sl => $sl}, "R$1")) {
		my $tmp = sprintf("XBee->Transmit(%x, %x, R%s) failed!\n", $sh, $sl, $1);
		error($tmp);
	    }
	} else {
	    debug("XBee->Send($1) Node not found!\n", 3);
	    $connection->MessageSend(
		to => "$from\@$server", body => "XBee->Send($1) Node not found!",
		resource => $resource);
	}
    # RFID-Test
    } elsif ($body =~ m/^rfid (.*)/i) {
	my ($rfid_id, $rfid_description, $rfid_lastseen, $rfid_validuntil, $rfid_valid);
	my $dateformat = $config->{dateformat};
	my $body = sprintf("%x:%x (%s)> RFID = %s", -1, -1, "TEST", $1);
	debug("Test->RFID($1)\n", 3);
	$connection->MessageSend(
	    to => $config->{sendTo}."\@".$config->{componentname}, body => $body,
	    resource => $config->{resource});

	my $sth = querydb("SELECT id, description, DATE_FORMAT(lastseen, '$dateformat'), DATE_FORMAT(validuntil, '$dateformat'), validuntil-now()>0 as valid FROM rfid WHERE tag='" . lc($1) . "'",
	    undef, \$rfid_id, \$rfid_description, \$rfid_lastseen, \$rfid_validuntil, \$rfid_valid);
	if ($sth->rows == 0) {
	    debug("Unknown RFID-Tag!\n", 3);
	    $rfidunknowntime = time + $config->{rfiddelay};
	    querydb("SELECT MAX(id) FROM rfid;", undef, \$rfid_id);
	    $rfid_id++;
	    my $query = qq{ INSERT INTO rfid (tag, description, lastseen, validuntil) VALUES ("$1", "Autoadded Tag #$rfid_id", NOW(), 0) };
	    $dbh->do($query);
	} else {
	    my $validstr = $rfid_valid ? "valid" : "INVALID";
	    if (!$rfid_valid) { $rfidunknowntime = time + $config->{rfiddelay}; }
	    debug("RFID-Tag #$rfid_id \"$rfid_description\" found and is $validstr.\n", 3);
	    if ($rfidunknowntime < time) {
		# later we will here open the door
	    } else {
		debug("RFID-Delay isn't over. (" . int($rfidunknowntime - time) . " secs to go...)\n", 3);
	    }
	}
	my $query = qq{ UPDATE rfid SET lastseen=NOW() WHERE id=$rfid_id LIMIT 1 };
	$dbh->do($query);
	$query = qq{ INSERT INTO rfid_log (tag_id) VALUES ($rfid_id) };
	$dbh->do($query);
    # Kein Befehl - ignorieren bzw. debuggen
    } else {
	if ($config->{debug} >= 5) {
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
# Parameter: messagestring, debuglevel
# Returns: nothing
sub debug {
    print strftime('%D %T [xjabber] DEBUG: ', localtime);
    if ($_[1] <= $config->{debug}) { print $_[0]; }
    return;
}

# Prints the given error message
# Parameter: messagestring
# Returns: nothing
sub error {
    print strftime('%D %T [xjabber] ERROR: ', localtime);
    print shift;
    return;
}

# Reads the next 3 tasks from the db and sends its content to the display-node
# Parameter: name of the destination-node
# Returns: nothing
sub sendGTasks {
    my $node = shift;

    debug("sendGTasks()\n", 2);
    if (my $tmp = resolveName($node)) {
	my ($gcal_task, $gcal_period);
	my $sh = $tmp->{sh}; my $sl = $tmp->{sl};

	my $sth = querydb("SELECT task, period FROM gcalendar ORDER BY id ASC LIMIT 3;", undef, \$gcal_task, \$gcal_period);
	for (my $i = 0; $i < $sth->rows; $i++) {
	    my $sendString = "G$i$gcal_task|$gcal_period";
	    if (!$xbee->tx({sh => $sh, sl => $sl}, $sendString)) {
		error("XBee->Transmit($node) failed!\n");
	    }
	    debug("XBee()->Display($sh, $sl, $sendString)\n", 4);
	    if ($i < $sth->rows) { $sth->fetch(); }
	}
    } else {
	debug("XBee->Send($node) Node not found!\n", 2);
    }
}

# Reads the logged in TS3-clients from the db and sends the content to
#   the display-node
# Parameter: name of the destination-node
# Returns: nothing
sub sendTS3User {
    my $node = shift;

    debug("sendTS3User()\n", 2);
    if (my $tmp = resolveName($node)) {
	my $client_nickname;
	my $sh = $tmp->{sh}; my $sl = $tmp->{sl};

	my $sth = querydb("SELECT client_nickname FROM teamspeak;", undef, \$client_nickname);
	for (my $i = 0; $i < $sth->rows; $i++) {
	    my $sendString = "T$i$client_nickname";
	    if (!$xbee->tx({sh => $sh, sl => $sl}, $sendString)) {
		error("XBee->Transmit($node) failed!\n");
	    }
	    debug("XBee()->Display($sh, $sl, $sendString)\n", 4);
	    if ($i < $sth->rows) { $sth->fetch(); }
	}
    } else {
	debug("XBee->Send($node) Node not found!\n", 2);
    }
}

# Reads weather data from the db and sends the content to the display-node
# Parameter: name of the destination-node
# Returns: nothing
sub sendWeather {
    my $node = shift;

    debug("sendWeather()\n", 2);
    if (my $tmp = resolveName($node)) {
	my ($condition_timecode, $condition_code, $condition_temp, $conditionString);
	my ($forecast_timecode, $forecast_low, $forecast_high, $forecast_code);
	my ($units_temperature, $units_distance, $units_pressure, $units_speed);
	my $dateformat = $config->{dateformat};
	my $sh = $tmp->{sh}; my $sl = $tmp->{sl};

	querydb("SELECT temperature, distance, pressure, speed FROM weather_units ORDER BY id DESC LIMIT 1;",
	  undef, \$units_temperature, \$units_distance, \$units_pressure, \$units_speed);
	my $sendString = "W3$units_temperature|$units_distance|$units_pressure|$units_speed";
	if (!$xbee->tx({sh => $sh, sl => $sl}, $sendString)) {
	    error("XBee->Transmit($node) failed!\n");
	}
	debug("XBee()->Display($sh, $sl, $sendString)\n", 4);

	querydb("SELECT DATE_FORMAT(timecode, '$dateformat'), code, temp FROM weather_condition ORDER BY id DESC LIMIT 1;",
	  undef, \$condition_timecode, \$condition_code, \$condition_temp);
	$conditionString = getCondString($condition_code);

	$sendString = "W0$condition_timecode|$condition_temp|$condition_code|$conditionString";
	if (!$xbee->tx({sh => $sh, sl => $sl}, $sendString)) {
	    error("XBee->Transmit($node) failed!\n");
	}
	debug("XBee()->Display($sh, $sl, $sendString)\n", 4);

	my $sth = querydb("SELECT DATE_FORMAT(timecode, '%w'), low, high, code FROM weather_forecast ORDER BY id DESC LIMIT 2;",
	  undef, \$forecast_timecode, \$forecast_low, \$forecast_high, \$forecast_code);
	for (my $i = 1; $i <= $sth->rows; $i++) {
	    $conditionString = getCondString($forecast_code);
	    $forecast_timecode += $i - 1;
	    $forecast_timecode %= 7;
	    my $weekday = @{$config->{weekdays}}[$forecast_timecode];
	    $sendString = "W$i$weekday|$forecast_low|$forecast_high|$forecast_code|$conditionString";
	    if (!$xbee->tx({sh => $sh, sl => $sl}, $sendString)) {
		error("XBee->Transmit($node) failed!\n");
	    }
	    debug("XBee()->Display($sh, $sl, $sendString)\n", 4);
	    if ($i < 2) { $sth->fetch(); }
	}
    } else {
	debug("XBee->Send($node) Node not found!\n", 2);
    }
}

# Resolves the XBee-Deviceaddress from its name
# Parameter: Devicename
# Returns: Deviceobject or undef
sub resolveName {
    my $name = shift;
    my ($sh, $sl) = (0, 0);

    debug("resolveName($name)\n", 4);

    for (my $i=0; $i<2; $i++) { # Sometimes it needs 2 attempts to resolve the name (object "busy"?)
	while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	    debug("$name -> $v->{ni} / $v->{sh}:$v->{sl}\n", 6);
	    if (lc($v->{ni}) eq $name) {
		$sh = $v->{sh};
		$sl = $v->{sl};
		return $v;
	    }
	}
    }

    return undef;
}

# Resolves the XBee-Devicename from its address
# Parameter: sh, sl
# Returns: Devicename or undef
sub resolveID {
    my ($sh, $sl) = @_;

    debug("resolveID($sh, $sl)\n", 4);

    for (my $i=0; $i<2; $i++) { # Sometimes it needs 2 attempts to resolve the name (object "busy"?)
	while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	    debug("$sh:$sl -> $v->{sh}:$v->{sl} / $v->{ni}\n", 6);
	    if (($sh eq $v->{sh}) && ($sl eq $v->{sl})) {
		return $v->{ni};
	    }
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
