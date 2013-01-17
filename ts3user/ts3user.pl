#!/usr/bin/perl
# ts3user.pl - Perl-script for gathering information from a ts3-server
#              Based on some code snippets from the teamspeak-forum
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
##########################################

my $config = YAML::LoadFile("/etc/xjabber/xjabber.conf");

##########################################

use strict;
use IO::Socket;
use YAML;
use DBI;

my $sock = IO::Socket::INET->new(
      PeerAddr    => "localhost",
      PeerPort    => 10011,
      Proto       => 'TCP',
      Autoflush   => 1,
) or die "ts3user.pl: Socket Failed To Start : $@";

print $sock "login serveradmin UaXVHTf9\n";
print $sock "use sid=1\n";
print $sock "clientlist\n";

my @users = ();
my $user = -1;

while(defined(my $data = <$sock>)) {
    if ($data =~ /error id=([^0?]\d+)/) {
        print "ts3user.pl: Error Fetching Clientlist\n";
        last;
    }
    elsif ($data =~ /client_nickname/) {
        my @lines = split(/\|/, $data);
        foreach (@lines) {
	    if ($_ !~ m/client_nickname=serveradmin/i) {
		$user++;
		($users[$user]->{clid}) = $_ =~ m/clid=(.*) cid=/i;
		($users[$user]->{cid}) = $_ =~ m/cid=(.*) client_database_id=/i;
		($users[$user]->{client_database_id}) = $_ =~ m/client_database_id=(.*) client_nickname=/i;
		($users[$user]->{client_nickname}) = $_ =~ m/client_nickname=(.*) client_type=/i;
		$users[$user]->{client_nickname} =~ s/\\s/ /gi;
		($users[$user]->{client_type}) = $_ =~ m/client_type=(.*)$/i;
	    }
        }
        last;
    }
}

if ($user >= 0) {
    my $dbh = DBI->connect("DBI:mysql:".$config->{mysqldb}, $config->{mysqluser}, $config->{mysqlpassword});
    my $query = qq{ TRUNCATE TABLE teamspeak };
    my $sth = $dbh->do($query);
    for (my $i=0; $i<=$user; $i++) {
	$query = qq{ INSERT into teamspeak (clid, cid, client_database_id, client_nickname, client_type) VALUES ("$users[$i]->{clid}", "$users[$i]->{cid}", "$users[$i]->{client_database_id}", "$users[$i]->{client_nickname}", "$users[$i]->{client_type}") };
	$sth = $dbh->do($query);
    }
    $dbh->disconnect();
}

close($sock);
exit(0);
