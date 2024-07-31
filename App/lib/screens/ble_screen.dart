import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:iotascamapp/api.dart';
import 'package:iotascamapp/common/loaders.dart';
import 'package:iotascamapp/location.dart';
import 'package:iotascamapp/screens/chat_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:alfred/alfred.dart';

class BleScreen extends StatefulWidget {
  const BleScreen({super.key});

  @override
  State<BleScreen> createState() => _BleScreenState();
}

class _BleScreenState extends State<BleScreen> {
  List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? targetCharacteristic;
  String? ssid,
      bssid,
      imagePath,
      localIp = "192.168.1.100",
      wifiName = "NAVI Smart Glasses";
  String wifiStatus = '';
  bool isLoading = false, isConnectingWifi = false;
  Uint8List? _receivedImage;
  final Alfred server = Alfred();
  @override
  void initState() {
    super.initState();
    checkPermissions();
  }

  Future<bool> enableRequiredServices() async {
    // bool wifiEnabled = false;
    bool bluetoothEnabled =
        await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
    bool locationEnabled = await Geolocator.isLocationServiceEnabled();
    List<ConnectivityResult> connections =
        await Connectivity().checkConnectivity(); // Check if connected to Wi-Fi
    bool wifiEnabled = connections.contains(ConnectivityResult.wifi);
    if (!wifiEnabled || !bluetoothEnabled || !locationEnabled) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Enable Services'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Please enable the following services:'),
                if (!wifiEnabled) const Text('• WiFi'),
                if (!bluetoothEnabled) const Text('• Bluetooth'),
                if (!locationEnabled) const Text('• Location'),
              ],
            ),
            // actions: <Widget>[
            //   TextButton(
            //     child: const Text('Enable'),
            //     onPressed: () async {
            //       if (!wifiEnabled) await WiFiForIoTPlugin.setEnabled(true);
            //       if (!bluetoothEnabled) await FlutterBluePlus.turnOn();
            //       if (!locationEnabled) {
            //         // For location, we still need to open settings as there's no direct API to enable it
            //         await Geolocator.openLocationSettings();
            //       }
            //       Navigator.of(context).pop();
            //     },
            //   ),
            // ],
          );
        },
      );

      // Check again after the user has (potentially) enabled the services
      List<ConnectivityResult> connectivityResult =
          await Connectivity().checkConnectivity();
      wifiEnabled = connectivityResult.contains(ConnectivityResult.wifi);
      bluetoothEnabled =
          await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
      locationEnabled = await Geolocator.isLocationServiceEnabled();
    }

    return wifiEnabled && bluetoothEnabled && locationEnabled;
  }

  void _saveImage(BuildContext context, String imagePath) async {
    Position? userLocation;
    Get.back();
    await WiFiForIoTPlugin.setEnabled(false);
    customLoadingOverlay("Loading description");
    try {
      userLocation = await determinePosition();
    } catch (e) {
      Get.back();
      customSnackbar('Error',
          'Failed to get user location\nEnsure that location is enabled & permissions are granted');
      return;
    }

    String latitude = userLocation.latitude.toString();
    String longitude = userLocation.longitude.toString();
    print("Image path inside save image: $imagePath"); //ye log hi nai hua
    final response = await Api().uploadImage(imagePath, latitude, longitude);
    Get.back(closeOverlays: true);
    if (response != {}) {
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
              description: response['description'], url: response['image_url']),
        ),
      );
      server.close();
    } else {
      customSnackbar('Error', 'Failed to upload image');
    }
  }

  @override
  void dispose() {
    server.close();
    super.dispose();
  }

  void checkPermissions() async {
    var status = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (status.values.every((status) => status.isGranted)) {
      bool servicesEnabled = await enableRequiredServices();
      if (servicesEnabled) {
        startScan();
      } else {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Services Not Enabled'),
              content: const Text(
                  'Some required services could not be enabled. The app may not function correctly.'),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    } else {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Permissions Required'),
            content: const Text(
                'Please grant all required permissions to use this feature.'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                  checkPermissions(); // Retry after user interaction
                },
              ),
            ],
          );
        },
      );
    }
  }

  void startScan() {
    resetData();

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 35));
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
    setState(() {
      isLoading = true;
    });
    customLoadingOverlay("Connecting to NAVI Smart Glasses");
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
      setState(() {
        isLoading = false;
      });
      Get.back();
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

                  handleReceivedValue(value);
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

  void handleReceivedValue(List<int> value) {
    // print("Received value: $value");
    String receivedString = utf8.decode(value);
    if (ssid == null) {
      List<String> split = receivedString.split('|');
      // print("Received split: $split");

      setState(() {
        ssid = split[0];
        bssid = split[1];
      });
      connectToWifi();
    }
  }

  Future<void> connectToWifi() async {
    if (ssid == null || ssid!.isEmpty) {
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
      await WiFiForIoTPlugin.setEnabled(true);

      print("Connecting to $ssid ${bssid ?? ''}");
      bool success = await WiFiForIoTPlugin.connect(ssid!,
          bssid: bssid, security: NetworkSecurity.NONE, timeoutInSeconds: 200);

      if (success) {
        // Wait for a moment to ensure connection is stable
        await Future.delayed(const Duration(seconds: 2));

        // Check if we're actually connected
        bool isConnected = await WiFiForIoTPlugin.isConnected();

        if (isConnected) {
          setState(() {
            wifiStatus = 'Connected to $ssid';
            isLoading = false;
          });
          Get.back();
          customLoadingOverlay("Getting image from device");
          // String? wifiIP = await NetworkInfo().getWifiIP();
          // print(wifiIP);
          createAPI();
          sendMessage("connected");

          await Future.delayed(const Duration(
              seconds: 1)); // Give some time for the Ameba to process
          //getImage();
          // await retryGetImage(3);
          //getImage();
        } else {
          setState(() {
            wifiStatus = 'Failed to verify connection';
          });
          Get.back();
          //if else mei hai
        }
      } else {
        setState(() {
          wifiStatus = 'Failed to connect to $ssid';
        });
        Get.back();
      }
    } catch (e) {
      print("Detailed error: $e");
      setState(() {
        wifiStatus = 'Error connecting to Wi-Fi: $e';
      });
      Get.back();
    } finally {
      setState(() {
        isConnectingWifi = false;
        isLoading = false;
      });
    }
  }

  Rx<Uint8List?> nwImage = Rx<Uint8List?>(null);

  Future<void> createAPI() async {
    //print my ip

    server.get('/', (req, res) {
      res.send("Wello Horld");
    });
    server.post('/upload', (req, res) async {
      print('Received image upload request');
      final body = await req.bodyAsJsonMap;
      final uploadedFile = (body['file'] as HttpBodyFileUpload);
      var fileBytes = (uploadedFile.content as List<int>);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/temp_image.jpg');
      await file.writeAsBytes(fileBytes);
      if (fileBytes.isNotEmpty) {
        setState(() {
          _receivedImage = Uint8List.fromList(fileBytes);
        });
      }
      if (!mounted) return;
      _saveImage(context, file.path);
      print('Image received');
      res.send('Image received');
    });

    await server.listen();
  }

  void sendMessage(String message) async {
    print('Sending message to device $message');
    if (targetCharacteristic != null) {
      try {
        // print('Sending message');
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

  void resetData() {
    setState(() {
      scanResults.clear();
      connectedDevice = null;
      targetCharacteristic = null;
      ssid = null;
      bssid = null;
      wifiStatus = '';
      isLoading = false;
      _receivedImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Demo'),
      ),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () => {checkPermissions(), startScan()},
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
                      const SizedBox(height: 10),
                      Text(wifiStatus),
                      const SizedBox(height: 20),
                      const SizedBox(height: 20),
                      if (_receivedImage != null && _receivedImage!.isNotEmpty)
                        Image.memory(
                          _receivedImage!,
                          fit: BoxFit.cover,
                          semanticLabel:
                              'Image clicked from NAVI Smart Glasses',
                          key: ValueKey(DateTime.now().millisecondsSinceEpoch),
                        )
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
