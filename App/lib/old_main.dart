import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

const String STA_DEFAULT_SSID = "STA_SSID";
const String STA_DEFAULT_PASSWORD = "STA_PASSWORD";
const NetworkSecurity STA_DEFAULT_SECURITY = NetworkSecurity.WPA;

const String AP_DEFAULT_SSID = "AP_SSID";
const String AP_DEFAULT_PASSWORD = "AP_PASSWORD";

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: BleScreen(),
    );
  }
}

class BleScreen extends StatefulWidget {
  const BleScreen({super.key});

  @override
  _BleScreenState createState() => _BleScreenState();
}

class _BleScreenState extends State<BleScreen> {
  List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? targetCharacteristic;
  bool isScanning = false;
  bool isLoading = false;
  List wifiNetworks = [];
  TextEditingController ssidController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    checkPermissions();
  }

  void checkPermissions() async {
    var status = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.nearbyWifiDevices
    ].request();

    if (status.values.every((status) => status.isGranted)) {
      startScan();
      scanForWiFi();
    } else {
      // Handle permission denied
      print("Permissions not granted");
    }
  }

  void startScan() {
    setState(() {
      isScanning = true;
      scanResults.clear();
    });
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results
            .where((result) => result.device.platformName == "AMB82-Custom")
            .toList();
      });
    }).onDone(() {
      setState(() {
        isScanning = false;
      });
      FlutterBluePlus.stopScan();
    });
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    setState(() {
      isScanning = false;
    });
  }

  void toggleScan() {
    if (isScanning) {
      stopScan();
    } else {
      startScan();
    }
  }

  Future<void> scanForWiFi() async {
    print('Scanning for Wi-Fi networks');
    wifiNetworks = await WiFiForIoTPlugin.loadWifiList();
    print(wifiNetworks);
    setState(() {});
  }

  Future<void> startHotspot() async {
    print('Starting hotspot');
    final bool isStarted = await WiFiForIoTPlugin.setWiFiAPEnabled(true);
    print('Hotspot started: $isStarted');
    // get the password of the hotspot

  }

  void connectToDevice(BluetoothDevice device) async {
    int attempts = 0;
    while (attempts < 3) {
      try {
        await device.connect();
        setState(() {
          connectedDevice = device;
        });
        discoverServices(device);
        break; // Exit loop if connection is successful
      } catch (e) {
        print("Failed to connect: $e");
        attempts++;
        await Future.delayed(
            const Duration(seconds: 2)); // Wait before retrying
      }
    }
  }

  void discoverServices(BluetoothDevice device) async {
    const String ServiceUUIDToMatch = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
    const String CharacteristicUUIDToMatch =
        "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
    try {
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        print("Service: ${service.uuid}");
        if (service.uuid.toString() == ServiceUUIDToMatch) {
          print("Found service");
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid.toString() == CharacteristicUUIDToMatch) {
              print("Characteristic: ${characteristic.uuid}");
              if (characteristic.properties.write ||
                  characteristic.properties.writeWithoutResponse) {
                setState(() {
                  targetCharacteristic = characteristic;
                });
                print("Found writable characteristic");
                break;
              }
            }
          }
        }
      }
    } catch (e) {
      print("Failed to discover services: $e");
    }
  }

  void sendMessage() async {
    if (targetCharacteristic != null) {
      try {
        String ssid = ssidController.text;
        String password = passwordController.text;
        String message = "Hi,SSID:$ssid,PASSWORD:$password";
        List<int> value = utf8.encode(message);

        if (targetCharacteristic!.properties.write) {
          await targetCharacteristic!.write(value, withoutResponse: false);
        } else if (targetCharacteristic!.properties.writeWithoutResponse) {
          await targetCharacteristic!.write(value, withoutResponse: true);
        } else {
          print("Characteristic is not writable");
          return;
        }

        print('Message sent');
      } catch (e) {
        print("Failed to send message: $e");
      }
    } else {
      print("No writable characteristic found");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Demo'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : connectedDevice == null
              ? Column(
                  children: [
                    ElevatedButton(
                      onPressed: toggleScan,
                      child: Text(isScanning ? 'Stop' : 'Scan'),
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.2,
                      child: ListView.builder(
                        itemCount: scanResults.length,
                        itemBuilder: (context, index) {
                          ScanResult result = scanResults[index];
                          return ListTile(
                            title: Text(result.device.platformName.isEmpty
                                ? "Unnamed"
                                : result.device.platformName),
                            subtitle: Text(result.device.remoteId.toString()),
                            onTap: () => connectToDevice(result.device),
                          );
                        },
                      ),
                    ),
                    // Padding(
                    //   padding: const EdgeInsets.all(8.0),
                    //   child: Column(
                    //     children: [
                          TextField(
                            controller: ssidController,
                            decoration: const InputDecoration(
                              labelText: 'SSID',
                            ),
                          ),
                          TextField(
                            controller: passwordController,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                            ),
                            obscureText: true,
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              // await scanForWiFi();
                              await startHotspot();
                            },
                            child: const Text('Scan for Wi-Fi'),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: wifiNetworks.length,
                              itemBuilder: (context, index) {
                                final network = wifiNetworks[index];
                                return ListTile(
                                  title: Text(network.ssid ?? 'Unnamed'),
                                  onTap: () {
                                    ssidController.text = network.ssid ?? '';
                                  },
                                );
                              },
                            ),
                        //   ),
                        // ],
                      // ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('Connected to ${connectedDevice!.platformName}'),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: sendMessage,
                      child: const Text('Send Hi and Wi-Fi Details'),
                    ),
                  ],
                ),
    );
  }
}
