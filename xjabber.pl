#!/usr/bin/perl -w

use strict;
use YAML;
use Net::XMPP;
use Net::Jabber;
use Device::SerialPort;
use Device::XBee::API;
use Digest::SHA qw(hmac_sha256_hex);

#############################################################

my $config = YAML::LoadFile("/etc/xjabber/xjabber.conf");

#############################################################

$SIG{HUP} = \&Stop;
$SIG{KILL} = \&Stop;
$SIG{TERM} = \&Stop;
$SIG{INT} = \&Stop;

my $serial_port_device = Device::SerialPort->new($config->{xbeedev}) || die $!;
$serial_port_device->baudrate($config->{xbeebaud});
$serial_port_device->databits($config->{xbeedatabits});
$serial_port_device->stopbits($config->{xbeestopbits});
$serial_port_device->parity($config->{xbeeparity});
$serial_port_device->read_char_time(0);
$serial_port_device->read_const_time(1000);

my $xbee = Device::XBee::API->new({fh => $serial_port_device}, api_mode_escape => 1) || die $!;
debug("XBee->Discover()...\n");
$xbee->discover_network();

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
    if (!defined($connection->Process(1))) {
	debug("XBee->Disconnected()\n");
	exit(254);
    }
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

	    if ($rx->{data} =~ m/C([0-9]*)/i) {
		my $hash = hmac_sha256_hex($1, $config->{hmacKey});
		my $body = sprintf("%x:%x (%s)> %s", $rx->{sh}, $rx->{sl}, $ni, "H$hash");
		$connection->MessageSend(
		    to => $config->{config}."\@".$config->{componentname}, body => $body,
    		    resource => $config->{resource});
		if (!$xbee->tx({sh => $rx->{sh}, sl => $rx->{sl}}, "H$hash")) {
		    print "XBee->Transmit() failed!\n";
		}
	    }
	}
    }
}

exit(0);

sub Stop {
    debug("Main->Exit()\n");
    $connection->Disconnect();
    exit(0);
}

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
		print "XBee->Transmit() failed!\n";
	    }
	} else {
	    debug("XBee->Send() Node not found!\n");
	}
    # send 13a200_406fffff message
    # Sende an 64bit-Adresse
    } elsif ($body =~ m/^send ([a-zA-Z0-9]*)_([a-zA-Z0-9]*) (.*)/i) {
	debug("XBee->Send($1_$2 => $3)\n");
        if (!$xbee->tx({sh => hex($1), sl => hex($2)}, $3)) {
            print "XBee->Transmit() failed!\n";
        }
    # broadcast message
    # Sende Nachricht per Broadcast
    } elsif ($body =~ m/^broadcast (.*)/i) {
	debug("XBee->Broadcast($1)\n");
	if (!$xbee->tx($1)) {
	    print "XBee->Transmit() failed!\n";
	}
    # open door 1
    # Öffnet Tür (1=Wohnungstür, 2=Haustür, 3=beide Türen)
    } elsif ($body =~ m/^open door ([1-3])/i) {
	debug("XBee->Open_Door($1)\n");
	my $found = 0;
	my $sh = 0; my $sl = 0;
	while (my ($k, $v) = each %{$xbee->{known_nodes}}) {
	    if (lc($v->{ni}) eq "door") {
		$sh = $v->{sh};
		$sl = $v->{sl};
		$found = 1;
	    }
	}
	if ($found == 1) {
	    if (!$xbee->tx({sh => $sh, sl => $sl}, "R$1")) {
		print "XBee->Transmit() failed!\n";
	    }
	} else {
	    debug("XBee->Send() Node not found!\n");
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

sub debug {
    if ($config->{debug}) { print shift; }
    return;
}
