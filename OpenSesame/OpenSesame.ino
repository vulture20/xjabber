#include "sha256.h"
#include "XBee.h"

int flatdoor = 2;
int housedoor = 3;

unsigned long lastsecret;
uint8_t hmacKey[] = {
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
};
uint8_t* expectedHmac;
char hmacString[65], responseString[65];
uint8_t payload[65];
int door = 0;

XBee xbee = XBee();
XBeeAddress64 addr64 = XBeeAddress64(0x00, 0x00);
ZBTxStatusResponse txStatus = ZBTxStatusResponse();
XBeeResponse response = XBeeResponse();
ZBRxResponse rx = ZBRxResponse();
ModemStatusResponse msr = ModemStatusResponse();

void setup() {
  pinMode(flatdoor, OUTPUT);
  pinMode(housedoor, OUTPUT);
  digitalWrite(flatdoor, HIGH);
  digitalWrite(housedoor, HIGH);
  Serial.begin(9600);
  xbee.setSerial(Serial);
  randomSeed(analogRead(0));

  uint8_t version[] = "LDoor v0.9";
  ZBTxRequest zbTx = ZBTxRequest(addr64, version, 10);
  xbee.send(zbTx);
}

void loop() {
  xbee.readPacket();
  if (xbee.getResponse().isAvailable()) {
    if (xbee.getResponse().getApiId() == ZB_RX_RESPONSE) {
      xbee.getResponse().getZBRxResponse(rx);
      
      if (rx.getOption() == ZB_PACKET_ACKNOWLEDGED) {
        flashLed(1, 500);
      } else {
        flashLed(5, 50);
      }

      char incomingByte = rx.getData()[0];
      if (incomingByte == 'R') {
        char secretstring[11] = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
        byte secretlength = 0;
        door = rx.getData()[1]-48;
        lastsecret = random(2147483646);
        payload[0] = 67; // 'C'
        sprintf(secretstring, "%lu", lastsecret);
        for (int i=0; i<sizeof(secretstring); i++) {
          secretlength = i;
          if (secretstring[i] == 0x00) break;
          payload[i+1] = secretstring[i];
        }
        ZBTxRequest zbTx = ZBTxRequest(addr64, payload, secretlength+1);
        xbee.send(zbTx);
        Sha256.initHmac(hmacKey, 32);
        Sha256.print(lastsecret);
        expectedHmac = Sha256.resultHmac();
        hmacToString(expectedHmac, hmacString);
      } else if (incomingByte == 'H') {
        for (int i=0; i<rx.getDataLength(); i++) {
          responseString[i] = rx.getData()[i+1];
        }
        responseString[64] = 0x00;
        if (compareStrings(hmacString, responseString)) {
          switch (door) {
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
        } else {
          flashLed(3, 200);
        }
      }
    }
  }
}

void hmacToString(uint8_t* hash, char hmac[65]) {
  for (int i=0; i<32; i++) {
    hmac[i*2] = "0123456789abcdef"[hash[i]>>4];
    hmac[(i*2)+1] = "0123456789abcdef"[hash[i]&0x0f];
  }
  hmac[64] = 0x00;
}

boolean compareStrings(char string1[65], char string2[65]) {
  for (int i=0; i<64; i++) {
    if (string1[i] != string2[i]) {
      return false;
    }
  }
  return true;
}

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

void sendPacket(uint8_t dataPayload[], byte sizeofPayload) {
  ZBTxRequest zbTx = ZBTxRequest(addr64, dataPayload, sizeofPayload);
  xbee.send(zbTx);
}

