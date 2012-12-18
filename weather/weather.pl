#!/usr/bin/perl -w
# weather.pl - Perl-script for gathering the weather information from
#              Yahoo! Weather. (http://developer.yahoo.com/weather/)
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

my $woeId = "639679"; # Bochum
my $unit = "c"; # f = Fahrenheit / c = Celsius (case sensitive!)

##########################################

my %conditionString = (
    0    => 'Tornado',			# tornado
    1    => 'Tropensturm',		# tropical storm
    2    => 'Wirbelsturm',		# hurricane
    3    => 'starke Unwetter',		# severe thunderstorms
    4    => 'Unwetter',			# thunderstorms
    5    => 'Schneeregen',		# mixed rain and snow
    6    => 'Graupelschauer',		# mixed rain and sleet
    7    => 'Schnee und Graupel',	# mixed snow ans sleet
    8    => 'gefrierender Nieselregen',	# freezing dizzle
    9    => 'Nieselregen',		# drizzle
    10   => 'gefrierender Regen',	# freezing rain
    11   => 'Schauer',			# showers
    12   => 'Schauer',			# showers
    13   => 'Schneegestöber',		# snow flurries
    14   => 'leichter Schneeregen',	# light snow showers
    15   => 'Schneetreiben',		# blowing snow
    16   => 'Schnee',			# snow
    17   => 'Hagel',			# hail
    18   => 'Graupel',			# sleet
    19   => 'Staub',			# dust
    20   => 'neblig',			# foggy
    21   => 'Nebel',			# haze
    22   => 'rauchig',			# smoky
    23   => 'stürmisch',		# blustery
    24   => 'windig',			# windy
    25   => 'kalt',			# cold
    26   => 'bewölkt',			# cloudy
    27   => 'meist wolkig (Nacht)',	# mostly cloudy (night)
    28   => 'meist wolkig (Tag)',	# mostly cloudy (day)
    29   => 'teils wolkig (Nacht)',	# partly cloudy (night)
    30   => 'teils wolkig (Tag)',	# partly cloudy (day)
    31   => 'klar (Nacht)',		# clear (night)
    32   => 'sonnig',			# sunny
    33   => 'heiter (Nacht)',		# fair (night)
    34   => 'heiter (Tag)',		# fair (day)
    35   => 'Regen und Hagel',		# mixed rain and hail
    36   => 'heiß',			# hot
    37   => 'vereinzelte Gewitter',	# isolated thunderstorms
    38   => 'vereinzelte Gewitter',	# scattered thunderstorms
    39   => 'vereinzelte Gewitter',	# scattered thunderstorms
    40   => 'vereinzelte Schauer',	# scattered showers
    41   => 'starker Schneefall',	# heavy snow
    42   => 'vereinzelter Schneeregen',	# scattered snow showers
    43   => 'starker Schneefall',	# heavy snow
    44   => 'teils wolkig',		# partly cloudy
    45   => 'Gewitterschauer',		# thundershowers
    46   => 'Schneeregen',		# snow showers
    47   => 'vereinzelte Gewitter',	# isolated thundershowers
    3200 => 'nicht verfügbar',		# not available
);

##########################################

use strict;
use WWW::Curl::Easy;

my $curl = WWW::Curl::Easy->new();

$curl->setopt(CURLOPT_HEADER, 1);
$curl->setopt(CURLOPT_URL, 'http://weather.yahooapis.com/forecastrss?w=' . $woeId . '&u=' . $unit);

my $response_body;
open(my $fp, ">", \$response_body);
$curl->setopt(CURLOPT_WRITEDATA, $fp);

my $retcode = $curl->perform();
my $day = 0;
my $condition = {};
my @forecast = ();
my $tmp = {};
my $wind = {};
my $location = {};
my $units = {};
my $atmosphere = {};
my $astronomy = {};

if ($retcode == 0) {
    my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
    foreach (split(/\n/, $response_body)) {
	if ($_ =~ m/<yweather:condition  text=\"(.*)\"  code=\"([0-9]*)\"  temp=\"([0-9]*)\"  date=\"(.*)\" \/>/) {
	    $condition->{text} = $1;
	    $condition->{code} = $2;
	    $condition->{temp} = $3;
	    $condition->{date} = $4;
	    $condition->{condstr} = $conditionString{$2};
	}
	if ($_ =~ m/<yweather:forecast day=\"(.*)\" date=\"(.*)\" low=\"([0-9]*)\" high=\"([0-9]*)\" text=\"(.*)\" code=\"([0-9]*)\" \/>/) {
	    $forecast[$day]{day} = $1;
	    $forecast[$day]{date} = $2;
	    $forecast[$day]{low} = $3;
	    $forecast[$day]{high} = $4;
	    $forecast[$day]{text} = $5;
	    $forecast[$day]{code} = $6;
	    $forecast[$day]{condstr} = $conditionString{$6};
	    $day++;
	}
	if ($_ =~ m/<yweather:wind chill=\"([0-9]*)\"   direction=\"([0-9]*)\"   speed=\"([0-9]*\.[0-9]*)\" \/>/) {
	    $wind->{chill} = $1;
	    $wind->{direction} = $2;
	    $wind->{speed} = $3;
	}
	if ($_ =~ m/<yweather:location city=\"(.*)\" region=\"(.*)\"   country=\"(.*)\"\/>/) {
	    $location->{city} = $1;
	    $location->{region} = $2;
	    $location->{country} = $3;
	}
	if ($_ =~ m/<yweather:units temperature=\"(.*)\" distance=\"(.*)\" pressure=\"(.*)\" speed=\"(.*)\"\/>/) {
	    $units->{temperature} = $1;
	    $units->{distance} = $2;
	    $units->{pressure} = $3;
	    $units->{speed} = $4;
	}
	if ($_ =~ m/<yweather:atmosphere humidity=\"([0-9]*)\"  visibility=\"(.*)\"  pressure=\"(.*)\"  rising=\"([0-9])\" \/>/) {
	    $atmosphere->{humidity} = $1;
	    $atmosphere->{visibility} = $2;
	    $atmosphere->{pressure} = $3;
	    $atmosphere->{rising} = $4;
	}
	if ($_ =~ m/<yweather:astronomy sunrise=\"(.*)\"   sunset=\"(.*)\"\/>/) {
	    $astronomy->{sunrise} = $1;
	    $astronomy->{sunset} = $2;
	}
    }
    print $condition->{condstr} . " bei " . $condition->{temp} . "°C\n";
    print "Vorhersage: " . $forecast[0]{condstr} . " bei $forecast[0]{low}-$forecast[0]{high}°C\n";
} else {
    print "weather.pl: An error happened: $retcode " . $curl->strerror($retcode) . " " . $curl->errbuf . "\n";
}
