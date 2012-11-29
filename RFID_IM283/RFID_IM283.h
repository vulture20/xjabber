/*
  RFID_IM283.h - Arduino/chipKit library support for the RFID Reader IM283
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

#ifndef RFID_IM283_h
#define RFID_IM283_h

#if defined(__AVR__)
  #if defined(ARDUINO) && ARDUINO >= 100
    #include "Arduino.h"
  #else
    #include "WProgram.h"
  #endif
#else
  #include "WProgram.h"
#endif

class RFID {
  public:
    RFID(void);
    RFID(uint8_t Found, uint8_t RST, uint8_t SCK, uint8_t SDT);
    void restartRFID(void);
    uint8_t foundRFID(void);
    uint8_t* getRFID(void);
    void readRFID(void);
  private:
    uint8_t _Found;
    uint8_t _RST;
    uint8_t _SCK;
    uint8_t _SDT;
    uint8_t _Tag[5];
};

#endif
