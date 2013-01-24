#include "sha256.h"
#include "XBee.h"
#include "RFID_IM283.h"

// Pin-Definitions
int flatdoor     = 2;
int housedoor    = 3;
int rfid_restart = 9;
int rfid_found   = 10;
int rfid_sck     = 11;
int rfid_sdt     = 12;

unsigned long lastsecret;
uint8_t* expectedHmac;
uint8_t payload[65];
char hmacString[65], responseString[65], rfidTag[5] = {0, 0, 0, 0, 0};
int door = 0;

// Enter HMAC-Key here and keep it secure!
uint8_t hmacKey[] = {
  0xf0, 0xdc, 0xc3, 0xde, 0x65, 0x38, 0x59, 0x26,
  0xc6, 0x51, 0x7a, 0x59, 0xa7, 0x3e, 0x34, 0x63,
  0x27, 0xfa, 0xa2, 0x73, 0x85, 0xa6, 0x38, 0xb7,
  0xd1, 0xc1, 0x4b, 0x1a, 0x6c, 0xd4, 0x37, 0x2d
};

// Initialize the XBee-Library
XBee xbee = XBee();
XBeeAddress64 addr64 = XBeeAddress64(0x00, 0x00); // always send to the coordinator (sh=0 & sl=0)
ZBTxStatusResponse txStatus = ZBTxStatusResponse();
XBeeResponse response = XBeeResponse();
ZBRxResponse rx = ZBRxResponse();
ModemStatusResponse msr = ModemStatusResponse();

// Initialize the RFID-Library
RFID RFID(rfid_found, rfid_restart, rfid_sck, rfid_sdt);

void setup() {
  // Setup IO-Pins
  pinMode(flatdoor, OUTPUT);
  pinMode(housedoor, OUTPUT);

  // My Relais are low-active
  digitalWrite(flatdoor, HIGH);
  digitalWrite(housedoor, HIGH);

  // Setup the Serial- and XBee-Interface
  Serial.begin(9600);
  xbee.setSerial(Serial);

  // Try to get some more or less real random numbers
  // more randomness means higher security for hmac hash
  randomSeed(analogRead(0));

  // Send a short version-string which will be ignored by the server
  uint8_t version[] = "#LDoor v0.9";
  ZBTxRequest zbTx = ZBTxRequest(addr64, version, 11);
  xbee.send(zbTx);
}

void loop() {
  // RFID-Tag has been found and will be read
  if (RFID.foundRFID()) {
    flashLed(1, 200); // Blink led for 200ms
    RFID.readRFID(); // Read the RFID-Tag
    memcpy(rfidTag, RFID.getRFID(), 5);
    payload[0] = byte('R'); // Set the trailing 'R'
    for (int i=0; i<5; i++) { // Convert the array of chars to a hex string
      payload[(i*2)+1] = "0123456789abcdef"[rfidTag[i]>>4];
      payload[(i*2)+2] = "0123456789abcdef"[rfidTag[i]&0x0f];
    }
    ZBTxRequest zbTx = ZBTxRequest(addr64, payload, 6); // Static size of 6 byte
    xbee.send(zbTx); // Send it
  }
  xbee.readPacket(100); // Try to read a XBee-Packet for 100ms
  if (xbee.getResponse().isAvailable()) { // Is a XBee-Packet available?
    if (xbee.getResponse().getApiId() == ZB_RX_RESPONSE) { // Was it a response to a previously sent packet?
      xbee.getResponse().getZBRxResponse(rx);

      if (rx.getOption() == ZB_PACKET_ACKNOWLEDGED) { // Packet was sent succesfully
        flashLed(1, 500); // Flash for 500ms
      } else {
        flashLed(5, 50); // Error: Flash 5 times for 50ms
      }

      char incomingByte = rx.getData()[0]; // Get the first byte => Opcode
      if (incomingByte == 'R') { // Opcode R = Request the random number
        char secretstring[11] = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
        byte secretlength = 0;
        door = rx.getData()[1]-48; // Which door should be opened? - store it for later
        lastsecret = random(2147483646); // Get a new random number (long int)
        payload[0] = byte('C'); // Set the trailing 'C'
        sprintf(secretstring, "%lu", lastsecret); // Convert number to string
        for (int i=0; i<sizeof(secretstring); i++) { // Copy the string into the payload array
          secretlength = i;
          if (secretstring[i] == 0x00) break; // 0-terminated - we're done
          payload[i+1] = secretstring[i];
        }
        ZBTxRequest zbTx = ZBTxRequest(addr64, payload, secretlength+1);
        xbee.send(zbTx); // Send it
        Sha256.initHmac(hmacKey, 32); // Initialize the HMAC-Library with the key
        Sha256.print(lastsecret); // Generate the hash of the random number
        expectedHmac = Sha256.resultHmac(); // Get the hash
        hmacToString(expectedHmac, hmacString); // Convert it to a string and store it for later
      } else if (incomingByte == 'H') { // Opcode H = Got a hash, check it and execute the command
        for (int i=0; i<rx.getDataLength(); i++) { // Get the data from the RFID-Packet
          responseString[i] = rx.getData()[i+1];
        }
        responseString[64] = 0x00; // Add a 0-byte for termination
        if (compareStrings(hmacString, responseString)) { // Is the hash the expected?
          switch (door) { // Open the corresponding door
            case 1:
              digitalWrite(flatdoor, LOW);
              delay(500);
              digitalWrite(flatdoor, HIGH);
              break;
            case 2:
              digitalWrite(housedoor, LOW);
              delay(500);
              digitalWrite(housedoor, HIGH);
              break;
            case 3:
              digitalWrite(flatdoor, LOW);
              digitalWrite(housedoor, LOW);
              delay(500);
              digitalWrite(flatdoor, HIGH);
              digitalWrite(housedoor, HIGH);
              break;
          }
          for (int i=0; i<sizeof(hmacString); i++) { // Delete the hmacString
            hmacString[i] = 0x00; // to prevent replay attacks
          }
        } else {
          flashLed(3, 200); // Flash 3 times for 200ms
        }
      } else if (incomingByte == 'E') { // Opcode E = Echo the given string
        for (int i=0; i<rx.getDataLength(); i++) { // Copy the string into the payload array
          payload[i] = rx.getData()[i+1];
        }
        ZBTxRequest zbTx = ZBTxRequest(addr64, payload, rx.getDataLength()-1);
        xbee.send(zbTx); // Send it
      }
    }
  }
}

// Converts a hmac hash byte-array to a string (array of chars)
void hmacToString(uint8_t* hash, char hmac[65]) {
  for (int i=0; i<32; i++) {
    hmac[i*2] = "0123456789abcdef"[hash[i]>>4];
    hmac[(i*2)+1] = "0123456789abcdef"[hash[i]&0x0f];
  }
  hmac[64] = 0x00;
}

// Compares two 65 byte-strings
// Returns true if both are the same
boolean compareStrings(char string1[65], char string2[65]) {
  for (int i=0; i<64; i++) {
    if (string1[i] != string2[i]) {
      return false;
    }
  }
  return true;
}

// Flash the led at pin 13
void flashLed(int times, int wait) {
  for (int i=0; i<times; i++) {
    digitalWrite(13, HIGH);
    delay(wait);
    digitalWrite(13, LOW);
    if (i+1<times) {
      delay(wait);
    }
  }
}

// Sends a packet via XBee to the coordinator
void sendPacket(uint8_t dataPayload[], byte sizeofPayload) {
  ZBTxRequest zbTx = ZBTxRequest(addr64, dataPayload, sizeofPayload);
  xbee.send(zbTx);
}

// RFID-Tag has been detected
boolean foundRFID() {
  return (digitalRead(rfid_found) == HIGH);
}

// Reset the RFID-Reader
void restartRFID() {
  digitalWrite(rfid_restart, HIGH);
  delay(5);
  digitalWrite(rfid_restart, LOW);
}

// Reads an RFID-Tag and stores the id in rfidTag
void readRFID() {
  for (int j=0; j<5; j++) {
    for (int i=0; i<8; i++) {
      byte dataBit = digitalRead(rfid_sdt); // First bit is available before first CLK-toggle!
      rfidTag[j] = rfidTag[j] << 1;
      rfidTag[j] += dataBit;
      digitalWrite(rfid_sck, HIGH);
      delay(10); // Maybe we can read faster - needs to be tested
      digitalWrite(rfid_sck, LOW);
    }
  }
}
