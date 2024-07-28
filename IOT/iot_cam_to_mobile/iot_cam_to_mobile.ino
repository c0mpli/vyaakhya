#include <WiFi.h>
#include "BLEDevice.h"
#include <stdlib.h>
#include <time.h>
#include "VideoStream.h"
#include "AmebaFatFS.h"
#include "Base64.h"
#include <WiFiUdp.h>

#define UDP_PORT 4210
#define MAX_PACKET_SIZE 1400  // Adjust based on your network's MTU
#define CUSTOM_SERVICE_UUID      "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX   "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX   "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#define IMAGE_FILENAME "image.jpg"
#define CHANNEL 0
#define FILENAME "image.jpg"
#define STRING_BUF_SIZE 100


BLEService CustomService(CUSTOM_SERVICE_UUID);
BLECharacteristic Rx(CHARACTERISTIC_UUID_RX);
BLECharacteristic Tx(CHARACTERISTIC_UUID_TX);


char ssid[] = "NAVI Smart Glasses";    // your network SSID (name)
char pass[] = "Password";  
char bssidStr[18];


const int MAX_CLIENT = 1;
WiFiClient client[MAX_CLIENT];
      // your network password
int status = WL_IDLE_STATUS;

WiFiServer wifiServer(80);  // Create a server on port 80
char server[] = "192.168.1.1";    // your server IP running HTTP server on PC

AmebaFatFS fs;
WiFiClient wifiClient;
BLEAdvertData advdata;
BLEAdvertData scndata;
bool notify = false;
bool deviceConnected = false;
bool readyReceived = false;
bool connectedReceived = false;
bool imageReadyReceived = false;

char buf[512];
char *p;
String filepath;
File file;
unsigned long lastCheckTime = 0;
const unsigned long checkInterval = 100; // Check every 100ms
const unsigned long timeout = 30000; // 30 seconds timeout

WiFiUDP udp;


// Video capture variables
VideoSetting config(VIDEO_FHD, CAM_FPS, VIDEO_JPEG, 1);
uint32_t img_addr = 0;
uint32_t img_len = 0;


void setupWiFiAP() {
    Serial.println("Setting up WiFi Access Point...");
    int result = WiFi.apbegin(ssid,pass);
    if (result == WL_CONNECTED) {
        Serial.println("Access Point setup successful.");
        Serial.print("AP IP address: ");
        Serial.println(WiFi.localIP());
        uint8_t bssid[6];
        WiFi.BSSID(bssid);
        snprintf(bssidStr, sizeof(bssidStr), "%02X:%02X:%02X:%02X:%02X:%02X", 
                 bssid[0], bssid[1], bssid[2], bssid[3], bssid[4], bssid[5]);
        Serial.print("AP BSSID: ");
        Serial.println(bssidStr);
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
        String receivedString = chr->readString();
        Serial.print("Received string: ");
        Serial.println(receivedString);
        
        if (receivedString == "ready") {
            Serial.println("Ready message received");
            readyReceived = true;
        }

        else if (receivedString == "connected") {
            Serial.println("Connected message received");
            connectedReceived = true;
        }

        else if (receivedString == "imageready"){
          Serial.println("Image ready message received");
          imageReadyReceived = true;
        }

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

// void captureAndSaveImage() {
//     Camera.getImage(CHANNEL, &img_addr, &img_len);
    
//     fs.begin();
//     File file = fs.open(String(fs.getRootPath()) + String(FILENAME));
//     if (file) {
//         file.write((uint8_t *)img_addr, img_len);
//         file.close();
//         Serial.println("Image saved to SD card");
//     } else {
//         Serial.println("Failed to open file for writing");
//     }
//     fs.end();
// }



// void sendImageViaHTTP(uint8_t* img_addr, uint32_t img_len) {
//     int encodedLen = base64_enc_len(img_len);
//     char* encodedData = (char*)malloc(encodedLen);
//     if (!encodedData) {
//         Serial.println("Failed to allocate memory for encoded data");
//         return;
//     }
//     base64_encode(encodedData, (char*)img_addr, img_len);

//     server.begin();
//     Serial.println("Server started");

//     while (true) {
//         for (int i = 0; i < MAX_CLIENT; i++) {
//             if (!client[i]) {
//                 client[i] = server.available();
//                 if (client[i]) {
//                     Serial.println("New client connected");
//                     Tx.writeString("incoming");
//                     if (notify) {
//                         Tx.notify(0);
//                     }
//                 }
//             }

//             if (client[i] && client[i].connected()) {
//                 if (client[i].available()) {
//                     String request = client[i].readStringUntil('\r');
//                     Serial.println(request);
//                     client[i].flush();

//                     if (request.indexOf("GET /image") != -1) {
//                         client[i].println("HTTP/1.1 200 OK");
//                         client[i].println("Content-Type: image/jpeg");
//                         client[i].println("Content-Length: " + String(encodedLen));
//                         client[i].println("Connection: close");
//                         client[i].println();
//                         client[i].print(encodedData);
//                         Serial.println("Image sent via HTTP");
//                         break;
//                     }
//                 }
//             }
//         }
//         // Break the loop after serving the image once
//         break;
//     }

//     free(encodedData);
//     server.stop();
// }


// void sendImageViaHTTP(uint8_t* img_addr, uint32_t img_len) {
//     Serial.println("Entering sendImageViaHTTP function");
//     Serial.print("Image address: ");
//     Serial.print((unsigned long)img_addr, HEX);
//     Serial.print(", Image length: ");
//     Serial.println(img_len);

//     int encodedLen = base64_enc_len(img_len);
//     Serial.print("Encoded length will be: ");
//     Serial.println(encodedLen);

//     char* encodedData = (char*)malloc(encodedLen);
//     if (!encodedData) {
//         Serial.println("Failed to allocate memory for encoded data");
//         return;
//     }
//     Serial.println("Memory allocated for encoded data");

//     base64_encode(encodedData, (char*)img_addr, img_len);
//     Serial.println("Image data encoded to base64");

//     unsigned long startTime = millis();
//     unsigned long elapsedTime = 0;
//     bool clientConnected = false;

//     Serial.println("Waiting for client connection...");

//     while (elapsedTime < timeout) {
//         if (millis() - lastCheckTime >= checkInterval) {
//             lastCheckTime = millis();
//             WiFiClient client = wifiServer.available();
//             if (client) {
//                 clientConnected = true;
//                 Serial.println("New client connected");
//                 Tx.writeString("incoming");
//                 if (notify) {
//                     Tx.notify(0);
//                 }

//                 Serial.println("Waiting for client request...");
//                 unsigned long requestStartTime = millis();
//                 while (client.connected() && !client.available() && millis() - requestStartTime < 5000) {
//                     delay(10);
//                 }

//                 if (client.available()) {
//                     String request = client.readStringUntil('\r');
//                     Serial.print("Received request: ");
//                     Serial.println(request);
//                     client.flush();

//                     if (request.indexOf("GET /image") != -1) {
//                         Serial.println("Image request received, sending response...");
//                         client.println("HTTP/1.1 200 OK");
//                         client.println("Content-Type: image/jpeg");
//                         client.print("Content-Length: ");
//                         client.println(encodedLen);
//                         client.println("Connection: close");
//                         client.println();
                        
//                         // Send data in chunks to avoid buffer overflow
//                         const int chunkSize = 1024;
//                         for (int i = 0; i < encodedLen; i += chunkSize) {
//                             int endIndex = min(i + chunkSize, encodedLen);
//                             client.write(encodedData + i, endIndex - i);
//                             Serial.print("Sent ");
//                             Serial.print(endIndex - i);
//                             Serial.println(" bytes");
//                             yield(); // Allow the WiFi stack to process
//                         }
                        
//                         Serial.println("Image sent via HTTP");
//                         free(encodedData);
//                         return;
//                     } else {
//                         Serial.println("Received invalid request, closing connection");
//                         client.stop();
//                     }
//                 } else {
//                     Serial.println("No request received from client, closing connection");
//                     client.stop();
//                 }
//             }
//         }
//         elapsedTime = millis() - startTime;
//         if (elapsedTime % 5000 == 0) {
//             Serial.print("Waiting for client... ");
//             Serial.print(elapsedTime / 1000);
//             Serial.println(" seconds elapsed");
//         }
//         yield(); // Allow other tasks to run
//     }

//     if (!clientConnected) {
//         Serial.println("Timeout: No client connected");
//     } else {
//         Serial.println("Timeout: Client connected but no valid request received");
//     }
//     free(encodedData);
// }


void broadcastImage(uint8_t* img_addr, uint32_t img_len) {
    int totalPackets = (img_len + MAX_PACKET_SIZE - 9) / (MAX_PACKET_SIZE - 8);
    
    IPAddress clientIP(192, 168, 1, 100);
    
    for (int i = 0; i < totalPackets; i++) {
        int headerSize = 8;
        int maxDataSize = MAX_PACKET_SIZE - headerSize;
        int dataSize = min(maxDataSize, (int)img_len - i * maxDataSize);
        int packetSize = headerSize + dataSize;

        uint8_t* packet = (uint8_t*)malloc(packetSize);
        if (!packet) {
            Serial.println("Failed to allocate memory for packet");
            return;
        }

        // Add header
        memcpy(packet, &i, 4);
        memcpy(packet + 4, &totalPackets, 4);

        // Add image data
        memcpy(packet + 8, img_addr + i * maxDataSize, dataSize);

        udp.beginPacket(clientIP, UDP_PORT);
        udp.write(packet, packetSize);
        udp.endPacket();

        free(packet);

        Serial.println("Sent packet ");
Serial.print(i + 1);
Serial.print("/");
Serial.print(totalPackets);
Serial.print(", size: ");
Serial.print(packetSize);
Serial.println(" bytes");
        //Serial.printf("Sent packet %d/%d, size: %d bytes\n", i+1, totalPackets, packetSize);
        
        delay(20);  // Small delay to prevent overwhelming the network
    }
}

void sendImageToFlutterAppViaUDP() {
    Serial.println("Broadcasting image via UDP");
    
    Serial.println("Capturing image...");
    Camera.getImage(CHANNEL, &img_addr, &img_len);
    Serial.print("Image captured. Address: ");
    Serial.print((unsigned long)img_addr, HEX);
    Serial.print(", Length: ");
    Serial.println(img_len);
    delay(3000);
    broadcastImage((uint8_t*)img_addr, img_len);
    Serial.println("Image broadcasting completed");
}

// void sendImageToFlutterAppViaHTTP() {
//     Serial.println("Sending image to Flutter app via HTTP");
    
//     Serial.println("Capturing image...");
//     Camera.getImage(CHANNEL, &img_addr, &img_len);
//     Serial.print("Image captured. Address: ");
//     Serial.print((unsigned long)img_addr, HEX);
//     Serial.print(", Length: ");
//     Serial.println(img_len);
    
//     sendImageViaHTTP((uint8_t*)img_addr, img_len);
//     Serial.println("Image sending process completed");
// }

// void sendImageToFlutterAppViaBLE() {
//     Serial.println("Sending image");
//     fs.begin();
//     File file = fs.open(String(fs.getRootPath()) + String(FILENAME));
//     if (!file) {
//         Serial.println("Failed to open file for reading");
//         return;
//     }

//     unsigned int fileSize = file.size();
//     uint8_t *fileData = (uint8_t *)malloc(fileSize);
//     if (!fileData) {
//         Serial.println("Failed to allocate memory for file data");
//         file.close();
//         return;
//     }

//     file.read(fileData, fileSize);
//     file.close();
//     fs.end();

//     // Encode the file data as Base64
//     int encodedLen = base64_enc_len(fileSize);
//     char *encodedData = (char *)malloc(encodedLen);
//     if (!encodedData) {
//         Serial.println("Failed to allocate memory for encoded data");
//         free(fileData);
//         return;
//     }
//     base64_encode(encodedData, (char *)fileData, fileSize);

//     // Send encoded data over BLE in chunks
//     const int chunkSize = 512;  // BLE packet size limit
//     for (int i = 0; i < encodedLen; i += chunkSize) {
//         int endIndex = min(i + chunkSize, encodedLen);
//         String chunk = String(encodedData).substring(i, endIndex);
//         Tx.writeString(chunk);
//         if (notify) {
//             Tx.notify(0);
//         }
//         delay(20);  // Small delay to ensure all packets are sent
//     }

//     free(fileData);
//     free(encodedData);
//     Serial.println("Image sent to Flutter app");
// }

// void sendImageToFlutterAppViaHTTP() {
//     Serial.println("Sending image");
//     fs.begin();
//     File file = fs.open(String(fs.getRootPath()) + String(FILENAME));
//     if (!file) {
//         Serial.println("Failed to open file for reading");
//         return;
//     }

//     unsigned int fileSize = file.size();
//     uint8_t* fileData = (uint8_t*)malloc(fileSize);
//     if (!fileData) {
//         Serial.println("Failed to allocate memory for file data");
//         file.close();
//         return;
//     }

//     file.read(fileData, fileSize);
//     file.close();
//     fs.end();

//     // Send the image via HTTP
//     sendImageViaHTTP(fileData, fileSize);

//     free(fileData);
//     Serial.println("Image sent to Flutter app");
// }


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
    BLE.configAdvert()->setMinInterval(100);
    BLE.configAdvert()->setMaxInterval(200);
    BLE.configAdvert()->updateAdvertParams();

    BLE.configServer(1);
    BLE.addService(CustomService);
  
    // Start advertising
    BLE.beginPeripheral();
    Serial.println("Advertising started");

    Camera.configVideoChannel(CHANNEL, config);
    Camera.videoInit();
    Camera.channelBegin(CHANNEL);

    // wifiServer.begin();
    // Serial.println("HTTP server started");

    udp.begin(UDP_PORT);
}

void loop() {
    if (BLE.connected(0) && !deviceConnected) {
        deviceConnected = true;
        Serial.println("Device connected. Waiting for ready message...");
    } else if (!BLE.connected(0) && deviceConnected) {
        deviceConnected = false;
        readyReceived = false;
        Serial.println("Device disconnected");
    }

    if (deviceConnected && readyReceived) {
        String wifiInfo = String(ssid);
        String bssidInfo = String(bssidStr);
        String combinedInfo = wifiInfo + "|" + bssidInfo;

        Tx.writeString(combinedInfo);
        Serial.println("Sending WiFi credentials:");
        Serial.println(combinedInfo);
        if (notify) {
            Tx.notify(0);
        }
        
        readyReceived = false; // Reset flag after sending credentials
    }

    if(deviceConnected && connectedReceived){
      // Serial.println("Inside connected");
      // IPAddress apIP = WiFi.localIP();
      // Serial.print("AP IP address: ");
      // Serial.println(apIP);
      // delay(3000);  // Wait 1 second


      //   Serial.println("New client connected");
      //   String currentLine = "";
      //   Camera.getImage(CHANNEL, &img_addr, &img_len);
      //   captureAndSaveImage();
      //   sendImageToFlutterApp2();
        
      //   Serial.println("Client disconnected");
      //   connectedReceived = false;

      Serial.println("Inside connected");
        IPAddress apIP = WiFi.localIP();
        Serial.print("AP IP address: ");
        sendImageToFlutterAppViaUDP();

        Serial.println(apIP);
        delay(3000);  // Wait 3 seconds        
        
        connectedReceived = false;
    }

    // if(deviceConnected && imageReadyReceived){
    //   Serial.println("Getting ready to send image");
    //   imageReadyReceived = false;
    // }

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