/*
  RFID_IM283.cpp - Arduino/chipKit library support for the RFID Reader IM283
  Copyright (C)2012-2013 Thorsten Schroepel. All right reserved
  
  If you make any modifications or improvements to the code, I would 
  appreciate that you share the code with me so that I might include 
  it in the next release. I can be contacted through 
  http://www.schroepel.net/.

  This library is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2.1 of the License, or (at your option) any later version.

  This library is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with this library; if not, write to the Free Software
  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
*/

#include "RFID_IM283.h"

RFID::RFID(void) {
}

RFID::RFID(uint8_t Found, uint8_t RST, uint8_t SCK, uint8_t SDT) {
  _Found = Found;
  _RST = RST;
  _SCK = SCK;
  _SDT = SDT;
  pinMode(_Found, INPUT);
  pinMode(_RST, OUTPUT);
  pinMode(_SCK, OUTPUT);
  pinMode(_SDT, INPUT);
  digitalWrite(_RST, LOW);
  digitalWrite(_SCK, LOW);
  this->restartRFID();
}

void RFID::restartRFID(void) {
  digitalWrite(_RST, HIGH);
  delay(10);
  digitalWrite(_RST, LOW);
}

uint8_t RFID::foundRFID(void) {
  return (digitalRead(_Found) == HIGH);
}

uint8_t* RFID::getRFID(void) {
  return _Tag;
}

void RFID::readRFID(void) {
  for (uint8_t j=0; j<5; j++) {
    for (uint8_t i=0; i<8; i++) {
      uint8_t dataBit = digitalRead(_SDT);
      _Tag[j] = _Tag[j] << 1;
      _Tag[j] += dataBit;
      digitalWrite(_SCK, HIGH);
      delay(10);
      digitalWrite(_SCK, LOW);
    }
  }
}
