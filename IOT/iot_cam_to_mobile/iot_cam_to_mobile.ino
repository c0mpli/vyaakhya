#include <WiFi.h>
#include "BLEDevice.h"
#include <stdlib.h>
#include <time.h>

#define CUSTOM_SERVICE_UUID      "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX   "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX   "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#define STRING_BUF_SIZE 100

BLEService CustomService(CUSTOM_SERVICE_UUID);
BLECharacteristic Rx(CHARACTERISTIC_UUID_RX);
BLECharacteristic Tx(CHARACTERISTIC_UUID_TX);

BLEAdvertData advdata;
BLEAdvertData scndata;

bool notify = false;
bool deviceConnected = false;

char ssid[] = "IoT_Hotspot";
char password[13]; // 12 characters + null terminator

void generatePassword() {
    const char charset[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    srand(time(NULL));
    for (int i = 0; i < 12; i++) {
        password[i] = charset[rand() % (sizeof(charset) - 1)];
    }
    password[12] = '\0';
}

void setupWiFiAP() {
    generatePassword();
    Serial.println("Setting up WiFi Access Point...");
    int result = WiFi.apbegin(ssid, password);
    if (result == WL_CONNECTED) {
        Serial.println("Access Point setup successful.");
        Serial.print("AP IP address: ");
        Serial.println(WiFi.localIP());
    } else {
        Serial.println("Failed to set up Access Point.");
        while (true); // Stop execution
    }
}

void readCB(BLECharacteristic* chr, uint8_t connID) {
    Serial.print("Characteristic ");
    Serial.print(chr->getUUID().str());
    Serial.print(" read by connection ");
    Serial.println(connID);
}

void writeCB(BLECharacteristic* chr, uint8_t connID) {
    Serial.print("Characteristic ");
    Serial.print(chr->getUUID().str());
    Serial.print(" write by connection ");
    Serial.println(connID);
    if (chr->getDataLen() > 0) {
        Serial.print("Received string: ");
        Serial.println(chr->readString());
    }
}

void notifCB(BLECharacteristic* chr, uint8_t connID, uint16_t cccd) {
    notify = (cccd & GATT_CLIENT_CHAR_CONFIG_NOTIFY);
    Serial.print(notify ? "Notifications enabled" : "Notifications disabled");
    Serial.print(" on Characteristic ");
    Serial.print(chr->getUUID().str());
    Serial.print(" for connection ");
    Serial.println(connID);
}

void setup() {
    Serial.begin(115200);
    Serial.println("BLE Custom Service Example");

    setupWiFiAP();

    // Configure advertising data
    advdata.addFlags(GAP_ADTYPE_FLAGS_LIMITED | GAP_ADTYPE_FLAGS_BREDR_NOT_SUPPORTED);
    advdata.addCompleteName("AMB82-Custom");
    scndata.addCompleteServices(BLEUUID(CUSTOM_SERVICE_UUID));

    // Configure Rx characteristic (Write)
    Rx.setWriteProperty(true);
    Rx.setWritePermissions(GATT_PERM_WRITE);
    Rx.setWriteCallback(writeCB);
    Rx.setBufferLen(STRING_BUF_SIZE);

    // Configure Tx characteristic (Read and Notify)
    Tx.setReadProperty(true);
    Tx.setReadPermissions(GATT_PERM_READ);
    Tx.setReadCallback(readCB);
    Tx.setNotifyProperty(true);
    Tx.setCCCDCallback(notifCB);
    Tx.setBufferLen(STRING_BUF_SIZE);

    // Add characteristics to the service
    CustomService.addCharacteristic(Rx);
    CustomService.addCharacteristic(Tx);

    // Initialize BLE
    BLE.init();
    BLE.configAdvert()->setAdvData(advdata);
    BLE.configAdvert()->setScanRspData(scndata);
    BLE.configServer(1);
    BLE.addService(CustomService);

    // Start advertising
    BLE.beginPeripheral();
    Serial.println("Advertising started");
}

void loop() {
    if (BLE.connected(0) && !deviceConnected) {
        delay(2000);
        deviceConnected = true;
        String wifiInfo = String(ssid) + "," + String(password);
        Tx.writeString(wifiInfo);
        Serial.println("Device connected. Sending WiFi credentials:");
        Serial.println(wifiInfo);
        if (notify) {
            Tx.notify(0);
        }
    } else if (!BLE.connected(0) && deviceConnected) {
        deviceConnected = false;
        Serial.println("Device disconnected");
    }

    if (Serial.available()) {
        String message = Serial.readString();
        Tx.writeString(message);
        Serial.print("Sending: ");
        Serial.println(message);
        if (BLE.connected(0) && notify) {
            Tx.notify(0);
        }
    }
    delay(100);
}