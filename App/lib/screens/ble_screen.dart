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
import 'package:udp/udp.dart';
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
  UDP? udpReceiver;
  List<Uint8List> imageChunks = [];
  int totalPackets = 0, receivedPackets = 0, connectionProgress = 0;
  final Alfred server = Alfred();
  @override
  void initState() {
    super.initState();
    checkPermissions();
    setupUdpListener();
    createAPI();
  }

  void setupUdpListener() async {
    udpReceiver = await UDP.bind(Endpoint.any(port: const Port(4210)));
    print("UDP receiver bound to port 4210");

    _startListening();
  }

  void _startListening() {
    print("Starting to listen for UDP packets");

    udpReceiver!.asStream().listen((Datagram? datagram) {
      if (datagram != null) {
        print("Received UDP packet from ${datagram.address}:${datagram.port}");

        handleReceivedPacket(datagram.data);
      }
    });
  }

  void _saveImage(BuildContext context, String imagePath) async {
    Position? userLocation;

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
      // onUploadSuccess(response['image_url'], response['description']);
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

  void handleReceivedPacket(Uint8List data) async {
    print("Handling received packet of length: ${data.length}");

    if (data.length < 8) {
      print("Received packet is too short: ${data.length} bytes");
      return;
    }

    int packetIndex = ByteData.view(data.buffer).getInt32(0, Endian.little);
    int totalPackets = ByteData.view(data.buffer).getInt32(4, Endian.little);

    print("Received packet $packetIndex of $totalPackets");

    if (data.length <= 8) {
      print("No image data in packet");
      return;
    }

    Uint8List imageData = data.sublist(8);
    print("Image data length: ${imageData.length}");
    // First 4 bytes: packet index
    // Next 4 bytes: total packets
    // Rest: image data

    if (packetIndex == 0) {
      // First packet, reset the image chunks
      imageChunks = List.filled(totalPackets, Uint8List(0));
      this.totalPackets = totalPackets;
      receivedPackets = 0;
    }

    imageChunks[packetIndex] = imageData;
    receivedPackets++;

    setState(() {
      // Update the UI to show progress
    });

    print("Received packets: $receivedPackets / $totalPackets");
    // Check if Last packet received
    if (packetIndex == totalPackets - 1) {
      //check if all packets are received
      if (receivedPackets == totalPackets) {
        // All packets received, combine them
        Get.back(); //ye loading description automatically kyu nai pakad raha??
        Uint8List fullImage =
            Uint8List.fromList(imageChunks.expand((x) => x).toList());
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/temp_image.jpg');
        await file.writeAsBytes(fullImage);
        setState(() {
          _receivedImage = fullImage;
          imagePath = file.path; // Store the path of the saved image
        });
        print('Image received and saved successfully at: $imagePath');
        _saveImage(context, file.path);
      } else {
        print("All packets not received");
        Get.back();
        customLoadingOverlay("Failed to get image");
        Future.delayed(const Duration(seconds: 2), () {
          Get.back();
        });
        //ye packets kabhi kabhi aate kabhi kabhi nai aisa kyu
      }
    }
    //if all the pakcets are received and they are not same as the total packets then we have Get.back() here

    // if (receivedPackets == totalPackets) {
  }

  @override
  void dispose() {
    udpReceiver?.close();
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
      startScan();
    } else {
      print("Permissions not granted");
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
            connectionProgress = 50;
          });
          await discoverServices(device);
          break;
        }

        await device.connect();
        setState(() {
          connectedDevice = device;
          connectionProgress = 50;
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
        connectionProgress = 0;
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
                  setState(() {
                    connectionProgress = 75;
                  });
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
            connectionProgress = 100;
            isLoading = false;
          });
          Get.back();
          customLoadingOverlay("Getting image from device");
          sendMessage("connected");
          await Future.delayed(const Duration(
              seconds: 1)); // Give some time for the Ameba to process
          //getImage();
          // await retryGetImage(3);
          //getImage();
        } else {
          setState(() {
            wifiStatus = 'Failed to verify connection';
            connectionProgress = 75;
          });
          Get.back();
          //if else mei hai
        }
      } else {
        setState(() {
          wifiStatus = 'Failed to connect to $ssid';
          connectionProgress = 75;
        });
        Get.back();
      }
    } catch (e) {
      print("Detailed error: $e");
      setState(() {
        wifiStatus = 'Error connecting to Wi-Fi: $e';
        connectionProgress = 75;
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
    server.post('/upload', (req, res) async {
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
      connectionProgress = 0;
      _receivedImage = null;
      imageChunks.clear();
      totalPackets = 0;
      receivedPackets = 0;
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
            onPressed: startScan,
            child: const Text('Refresh'),
          ),
          // if (_receivedImage != null && _receivedImage!.isNotEmpty)
          //   Image.memory(
          //     _receivedImage!,
          //     fit: BoxFit.cover,
          //     semanticLabel: 'Image clicked from NAVI Smart Glasses',
          //     key: ValueKey(DateTime.now().millisecondsSinceEpoch),
          //   )
          // else
          //   const Text('No image received yet'),
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
                      // ElevatedButton(
                      //   onPressed: () => retryGetImage(3),
                      //   child: const Text('Get Image'),
                      // ),
                      const SizedBox(height: 20),
                      Text(
                          'Received packets: $receivedPackets / $totalPackets'),
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
