#!/usr/bin/perl -w
# gcalendar.pl - Perl-script for gathering the google calendar
#		 using the google python-script.
# !!!! The config of googlecl (~/.config/googlecl/config) has to be edited !!!!
# Edit/Insert this line: date_print_format = %d.%m.%Y %H:%M:%S
#
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
use YAML;
use DBI;
use POSIX;

my $dbh = DBI->connect("DBI:mysql:".$config->{mysqldb}, $config->{mysqluser}, $config->{mysqlpassword});
my $query = qq{ TRUNCATE TABLE gcalendar; };
my $sth = $dbh->do($query);

open(my $GCAL, "-|", "/usr/bin/google calendar --delimiter='|' list | tail -n +3") or die("Couldn't launch the google-script!");
while (<$GCAL>) {
  $_ =~ s/ü/ue/g;
  $_ =~ s/ä/ae/g;
  $_ =~ s/ö/oe/g;
  $_ =~ s/Ü/Ue/g;
  $_ =~ s/Ä/Ae/g;
  $_ =~ s/Ö/Oe/g;
  $_ =~ s/ß/ss/g;
  chomp($_);
  my @data = split(/\|/, $_);
  my @zeitraum = split(/ - /, $data[1]);
  my ($from_day, $from_month, $from_year, $from_hour, $from_minute, $from_second) = $zeitraum[0] =~ m/(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2}):(\d{2})/;
  my ($to_day, $to_month, $to_year, $to_hour, $to_minute, $to_second) = $zeitraum[1] =~ m/(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2}):(\d{2})/;
  $query = qq{ INSERT INTO gcalendar (task, period, period_from, period_to) VALUES ("$data[0]", "$data[1]", "$from_year-$from_month-$from_day $from_hour:$from_minute:$from_second", "$to_year-$to_month-$to_day $to_hour:$to_minute:$to_second"); };
  $sth = $dbh->do($query);
}
close($GCAL);
