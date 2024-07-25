import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

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
  String? ssid;
  String? bssid;
  bool isConnectingWifi = false;
  String wifiStatus = '';

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
    ].request();

    if (status.values.every((status) => status.isGranted)) {
      startScan();
    } else {
      print("Permissions not granted");
    }
  }

  void startScan() {
    setState(() {
      scanResults.clear(); // Clear previous results
      connectedDevice = null; // Reset connected device
      ssid = null; // Reset SSID
      bssid = null;
      wifiStatus = ''; // Reset Wi-Fi status
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results
            .where((result) => result.device.platformName == "AMB82-Custom")
            .toList();
      });
    }).onDone(() {
      FlutterBluePlus.stopScan();
    });
  }

  void connectToDevice(BluetoothDevice device) async {
    int attempts = 0;

    Future<BluetoothConnectionState> getCurrentConnectionState(
        BluetoothDevice device) async {
      return await device.connectionState.first;
    }

    while (attempts < 3) {
      try {
        BluetoothConnectionState connectionState =
            await getCurrentConnectionState(device);

        if (connectionState == BluetoothConnectionState.connected) {
          setState(() {
            connectedDevice = device;
          });
          await discoverServices(device);
          //sendMessage("ready"); // Add this line

          break;
        }

        await device.connect();
        setState(() {
          connectedDevice = device;
        });
        await discoverServices(device);
        break;
      } catch (e) {
        print("Failed to connect: $e");
        attempts++;
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (attempts == 3) {
      print("Failed to connect after 3 attempts");
    }
  }

  Future<void> discoverServices(BluetoothDevice device) async {
    const String ServiceUUIDToMatch = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
    const String CharacteristicUUIDToMatch =
        "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
    const String NotifyCharacteristicUUIDToMatch =
        "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

    try {
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid.toString() == ServiceUUIDToMatch) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            //print("Characteristic $characteristic");
            if (characteristic.characteristicUuid.toString() ==
                CharacteristicUUIDToMatch) {
              if (characteristic.properties.write ||
                  characteristic.properties.writeWithoutResponse) {
                setState(() {
                  targetCharacteristic = characteristic;
                });
              }
            } else if (characteristic.characteristicUuid.toString() ==
                NotifyCharacteristicUUIDToMatch) {
              if (characteristic.properties.notify) {
                print("Setting notify value");
                await characteristic.setNotifyValue(true);
                sendMessage("ready");
                characteristic.onValueReceived.listen((value) {
                  print("Received value: $value");
                  _handleReceivedValue(value);
                });
              }
            }
          }
        }
      }
    } catch (e) {
      print("Failed to discover services: $e");
    }
  }

  void _handleReceivedValue(List<int> value) {
    print("Received value: $value");
    String receivedString = utf8.decode(value);
    List<String> split = receivedString.split('|');
    print("Received split: $split");

    setState(() {
      ssid = split[0];
      bssid = split[1];
    });
    _connectToWifi();
  }

  Future<void> _connectToWifi() async {
    if (ssid == null || ssid!.isEmpty) {
      if (bssid == null || bssid!.isEmpty) {
        setState(() {
          wifiStatus = 'BSSID & SSID is missing';
        });
        return;
      }
      setState(() {
        wifiStatus = 'SSID is missing';
      });
      return;
    }

    setState(() {
      isConnectingWifi = true;
      wifiStatus = 'Connecting to Wi-Fi...';
    });

    try {
      await WiFiForIoTPlugin.setEnabled(true, shouldOpenSettings: false);

      print("Connecting to $ssid $bssid");
      bool success = await WiFiForIoTPlugin.connect(ssid!,
          bssid: bssid!, security: NetworkSecurity.NONE, timeoutInSeconds: 30);
      print("Connection result: $success");
      if (success) {
        // Wait for a moment to ensure connection is stable
        await Future.delayed(const Duration(seconds: 2));

        // Double-check if we're actually connected
        //final info = NetworkInfo();
        //String? connectedSSID = await info.getWifiName();

        if (success) {
          setState(() {
            wifiStatus = 'Connected to $ssid';
          });
        } else {
          setState(() {
            wifiStatus = 'Connection verified failed.';
          });
        }
      } else {
        setState(() {
          wifiStatus = 'Failed to connect to $ssid';
        });
      }
    } catch (e) {
      print("Detailed error: $e");
      setState(() {
        wifiStatus = 'Error connecting to Wi-Fi: $e';
      });
    } finally {
      setState(() {
        isConnectingWifi = false;
      });
    }
  }

  void sendMessage(String message) async {
    print('Sending message to device $message');
    if (targetCharacteristic != null) {
      try {
        print('Sending message');
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Demo'),
      ),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: startScan,
            child: const Text('Refresh'),
          ),
          Expanded(
            child: connectedDevice == null
                ? ListView.builder(
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
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('Connected to ${connectedDevice!.platformName}'),
                      const SizedBox(height: 20),
                      if (ssid != null) ...[
                        Text('Hotspot SSID: $ssid'),
                        const SizedBox(height: 20),
                        Text('Wi-Fi Status: $wifiStatus'),
                        if (isConnectingWifi)
                          const CircularProgressIndicator()
                        else
                          ElevatedButton(
                            onPressed: _connectToWifi,
                            child: const Text('Connect to Wi-Fi'),
                          ),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => sendMessage("Hi"),
                        child: const Text('Send Hi'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
