-- phpMyAdmin SQL Dump
-- version 3.3.7deb7
-- http://www.phpmyadmin.net
--
-- Host: localhost
-- Erstellungszeit: 19. Dezember 2012 um 13:20
-- Server Version: 5.1.66
-- PHP-Version: 5.3.3-7+squeeze14

SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

--
-- Datenbank: `xjabber`
--

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `weather_astronomy`
--

CREATE TABLE IF NOT EXISTS `weather_astronomy` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `timecode` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `sunrise` varchar(15) COLLATE ascii_bin NOT NULL,
  `sunset` varchar(15) COLLATE ascii_bin NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=ascii COLLATE=ascii_bin;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `weather_atmosphere`
--

CREATE TABLE IF NOT EXISTS `weather_atmosphere` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `timecode` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `humidity` int(11) NOT NULL,
  `visibility` int(11) NOT NULL,
  `pressure` float NOT NULL,
  `rising` int(1) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=ascii COLLATE=ascii_bin;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `weather_condition`
--

CREATE TABLE IF NOT EXISTS `weather_condition` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `timecode` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `text` varchar(25) CHARACTER SET latin1 NOT NULL,
  `code` int(11) NOT NULL,
  `temp` int(11) NOT NULL,
  `date` varchar(15) CHARACTER SET latin1 NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=ascii COLLATE=ascii_bin;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `weather_condString`
--

CREATE TABLE IF NOT EXISTS `weather_condString` (
  `id` int(10) unsigned NOT NULL,
  `conditionString` varchar(25) COLLATE ascii_bin NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=ascii COLLATE=ascii_bin;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `weather_forecast`
--

CREATE TABLE IF NOT EXISTS `weather_forecast` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `timecode` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `day` varchar(3) COLLATE ascii_bin NOT NULL,
  `date` varchar(15) COLLATE ascii_bin NOT NULL,
  `low` int(11) NOT NULL,
  `high` int(11) NOT NULL,
  `text` varchar(25) COLLATE ascii_bin NOT NULL,
  `code` int(11) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=ascii COLLATE=ascii_bin;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `weather_location`
--

CREATE TABLE IF NOT EXISTS `weather_location` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `timecode` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `city` varchar(30) COLLATE ascii_bin NOT NULL,
  `region` varchar(30) COLLATE ascii_bin NOT NULL,
  `country` varchar(30) COLLATE ascii_bin NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=ascii COLLATE=ascii_bin;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `weather_units`
--

CREATE TABLE IF NOT EXISTS `weather_units` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `timecode` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `temperature` varchar(1) COLLATE ascii_bin NOT NULL,
  `distance` varchar(2) COLLATE ascii_bin NOT NULL,
  `pressure` varchar(2) COLLATE ascii_bin NOT NULL,
  `speed` varchar(3) COLLATE ascii_bin NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=ascii COLLATE=ascii_bin;

-- --------------------------------------------------------

--
-- Tabellenstruktur für Tabelle `weather_wind`
--

CREATE TABLE IF NOT EXISTS `weather_wind` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `timecode` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `chill` int(11) NOT NULL,
  `direction` int(11) NOT NULL,
  `speed` int(11) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=ascii COLLATE=ascii_bin;

