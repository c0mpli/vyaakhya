#include <WiFi.h>
#include "BLEDevice.h"
#include <stdlib.h>
#include <time.h>
#include "Base64.h"
#include "StreamIO.h"
#include "Base64.h"

#define UDP_PORT 4210
#define MAX_PACKET_SIZE 1400  // Adjust based on your network's MTU
#define CUSTOM_SERVICE_UUID      "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX   "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX   "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#define IMAGE_FILENAME "image.jpg"
#define CHANNEL 0
#define FILENAME "image.jpg"
#define STRING_BUF_SIZE 100
#define API_ENDPOINT "http://192.168.1.1:3000/upload"


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

WiFiUDP udp;


// constants won't change. They're used here to set pin numbers:
const int buttonPin = 2;  // the number of the pushbutton pin
const int ledPin = 13;    // the number of the LED pin

// Variables will change:
int ledState = HIGH;        // the current state of the output pin
int buttonState;            // the current reading from the input pin

// the following variables are unsigned longs because the time, measured in
// milliseconds, will quickly become a bigger number than can be stored in an int.
bool isImageDescriptionShown = false, isImageClicked = false;
unsigned long lastDebounceTime = 0;
unsigned long debounceDelay = 30;  // Adjust this value if needed
bool lastButtonState = LOW;
bool buttonPressed = false;
const unsigned long buttonClickedDebounceDelay = 500; // 500ms debounce for button clicked message
unsigned long lastButtonClickedTime = 0;
bool buttonClickedMessageSent = false;



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


void sendImageToAPI(uint8_t* img_addr, uint32_t img_len) {
    WiFiClient client;
    
    Serial.print("Connecting to API endpoint: ");
    Serial.println(API_ENDPOINT);
    
    if (client.connect("192.168.1.100", 3000)) {  // Assuming the server is running on port 3000
        Serial.println("Connected to server");
        
        // Prepare the HTTP POST request
        String boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW";
        String body = "--" + boundary + "\r\n";
        body += "Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n";
        body += "Content-Type: image/jpeg\r\n\r\n";
        
        String end = "\r\n--" + boundary + "--\r\n";
        
        int contentLength = body.length() + img_len + end.length();
        
        // Send the HTTP POST request headers
        client.println("POST /upload HTTP/1.1");
        client.println("Host: 192.168.1.100:3000");
        client.println("Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW");
        client.println("Content-Length: " + String(contentLength));
        client.println("Connection: close");
        client.println();
//         POST /upload HTTP/1.1
// Host: 192.168.1.1:3000
// Content-Length: 241
// Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW

// ------WebKitFormBoundary7MA4YWxkTrZu0gW
// Content-Disposition: form-data; name="file"; filename="postman-cloud:///1eeacc0e-4a04-40f0-b66e-7bc1da1265be"
// Content-Type: <Content-Type header here>

// (data)
// ------WebKitFormBoundary7MA4YWxkTrZu0gW--
        // Send the body
        client.print(body);
        
        // Send the image data
        client.write(img_addr, img_len);
        
        // Send the closing boundary
        client.print(end);
        
        // Wait for the server's response
        while (client.connected()) {
            String line = client.readStringUntil('\n');
            if (line == "\r") {
                Serial.println("Headers received");
                break;
            }
        }
        
        // Read the response
        while (client.available()) {
            String line = client.readStringUntil('\n');
            Serial.println(line);
        }
        
        client.stop();
        Serial.println("Request completed");
    } else {
        Serial.println("Connection to server failed");
    }
}

void captureAndSendImageToAPI() {
    Serial.println("Capturing and sending image to API");
    
    Serial.println("Capturing image...");
    Camera.getImage(CHANNEL, &img_addr, &img_len);
    Serial.print("Image captured. Address: ");
    Serial.print((unsigned long)img_addr, HEX);
    Serial.print(", Length: ");
    Serial.println(img_len);
    
    sendImageToAPI((uint8_t*)img_addr, img_len);
    Serial.println("Image sending process completed");
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

    pinMode(buttonPin, INPUT);


    // wifiServer.begin();
    // Serial.println("HTTP server started");

    //udp.begin(UDP_PORT);
}

void loop() {
     int reading = digitalRead(buttonPin);

    if (reading != lastButtonState) {
        lastDebounceTime = millis();
    }

    if ((millis() - lastDebounceTime) > debounceDelay) {
        if (reading != buttonState) {
            buttonState = reading;

            if (buttonState == HIGH && !buttonPressed) {
                Serial.println("Button Clicked");
                buttonPressed = true;
                Tx.writeString("buttonclicked");
                if(notify){
                  Tx.notify(0);
                }
                // // Add your button press actions here
                // if (!isImageDescriptionShown && deviceConnected && !buttonClickedMessageSent) {
                //     unsigned long currentTime = millis();
                //     if (currentTime - lastButtonClickedTime > buttonClickedDebounceDelay) {
                //         Tx.writeString("buttonclicked");
                //         if (notify) {
                //             Tx.notify(0);
                //         }
                //         isImageClicked = true;
                //         buttonClickedMessageSent = true;
                //         lastButtonClickedTime = currentTime;
                //         Serial.println("Button clicked message sent");
                //     }
                // }
            } else if (buttonState == LOW) {
                buttonPressed = false;
                buttonClickedMessageSent = false;
            }
        }
    }

    lastButtonState = reading;

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

    if(buttonState && !isImageDescriptionShown && deviceConnected){
      Tx.writeString("buttonclicked");
      if(notify){
        Tx.notify(0);
      }
      isImageClicked = true;
    }

    if(isImageClicked && !isImageDescriptionShown && deviceConnected){

    }
    

    if(deviceConnected && connectedReceived){

      Serial.println("Inside connected");
        IPAddress apIP = WiFi.localIP();
        Serial.print("AP IP address: ");
        //sendImageToFlutterAppViaUDP();
        captureAndSendImageToAPI();

        Serial.println(apIP);
        delay(3000);  // Wait 3 seconds        
        
        connectedReceived = false;
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