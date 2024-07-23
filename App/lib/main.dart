import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
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
  String? password;

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
      // Handle permission denied
      print("Permissions not granted");
    }
  }

  void startScan() {
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
    while (attempts < 3) {
      try {
        await device
            .disconnect(); // Ensure the device is disconnected before trying to connect
        await device.connect();
        setState(() {
          connectedDevice = device;
        });
        await discoverServices(device);
        break; // Exit loop if connection is successful
      } catch (e) {
        print("Failed to connect: $e");
        attempts++;
        await Future.delayed(
            const Duration(seconds: 2)); // Wait before retrying
      }
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
            print("Characteristic $characteristic");
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
    List<String> parts = receivedString.split(',');
    if (parts.length == 2) {
      setState(() {
        ssid = parts[0];
        password = parts[1];
      });
    }
  }

  void sendMessage() async {
    if (targetCharacteristic != null) {
      try {
        print('Sending message');
        List<int> value = utf8.encode("Hi");
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
      body: connectedDevice == null
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
                if (ssid != null && password != null) ...[
                  Text('Hotspot SSID: $ssid'),
                  Text('Hotspot Password: $password'),
                  const SizedBox(height: 20),
                ],
                ElevatedButton(
                  onPressed: sendMessage,
                  child: const Text('Send Hi'),
                ),
              ],
            ),
    );
  }
}
