import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:udp/udp.dart';

import 'package:iotascamapp/api.dart';
import 'package:iotascamapp/location.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:path_provider/path_provider.dart';

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

  @override
  void initState() {
    super.initState();
    checkPermissions();
    setupUdpListener();
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

    if (receivedPackets == totalPackets) {
      // All packets received, combine them
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

      _saveImage(context, this);
    }
  }

  @override
  void dispose() {
    udpReceiver?.close();
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

  // Future<void> getImage() async {
  //   print('Getting image from device');
  //   try {
  //     //sendMessage("imageready");
  //     //_connectToWifi();

  //     final response =
  //         await http.get(Uri.parse('http://192.168.1.1/image')).timeout(
  //       const Duration(seconds: 30),
  //       onTimeout: () {
  //         throw TimeoutException(
  //             'The connection has timed out, please try again!');
  //       },
  //     );

  //     print('Response status: ${response.statusCode}');
  //     print('Response headers: ${response.headers}');
  //     print('Response body length: ${response.bodyBytes.length}');
  //     if (response.statusCode == 200) {
  //       setState(() {
  //         _receivedImage = Uint8List.fromList(response.bodyBytes);
  //       });
  //       print('Image received successfully');
  //     } else {
  //       print('Failed to load image: ${response.statusCode}');
  //       setState(() {
  //         wifiStatus = 'Failed to load image: ${response.statusCode}';
  //       });
  //     }
  //   } on SocketException catch (e) {
  //     print('Socket Error: $e');
  //     setState(() {
  //       wifiStatus = 'Network Error: Unable to connect to the device';
  //     });
  //   } on TimeoutException catch (e) {
  //     print('Timeout Error: $e');
  //     setState(() {
  //       wifiStatus = 'Connection timed out. Please try again.';
  //     });
  //   } catch (e) {
  //     print('Error: $e');
  //     setState(() {
  //       wifiStatus = 'An error occurred: $e';
  //     });
  //   }
  // }

  void handleReceivedValue(List<int> value) {
    print("Received value: $value");
    String receivedString = utf8.decode(value);
    if (ssid == null) {
      List<String> split = receivedString.split('|');
      print("Received split: $split");

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
        }
      } else {
        setState(() {
          wifiStatus = 'Failed to connect to $ssid';
          connectionProgress = 75;
        });
      }
    } catch (e) {
      print("Detailed error: $e");
      setState(() {
        wifiStatus = 'Error connecting to Wi-Fi: $e';
        connectionProgress = 75;
      });
    } finally {
      setState(() {
        isConnectingWifi = false;
        isLoading = false;
      });
    }
  }

  // Future<void> retryGetImage(int maxRetries) async {
  //   for (int i = 0; i < maxRetries; i++) {
  //     try {
  //       await getImage();
  //       if (_receivedImage != null) {
  //         break; // Successfully got the image, exit the loop
  //       }
  //     } catch (e) {
  //       print('Attempt ${i + 1} failed: $e');
  //       if (i == maxRetries - 1) {
  //         setState(() {
  //           wifiStatus = 'Failed to get image after $maxRetries attempts';
  //         });
  //       } else {
  //         await Future.delayed(
  //             const Duration(seconds: 2)); // Wait before retrying
  //       }
  //     }
  //   }
  // }

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
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 50),
                    child: LinearProgressIndicator(
                      value: connectionProgress / 100,
                      minHeight: 10,
                      backgroundColor: Colors.grey[300],
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Connecting...'),
                ],
              ),
            )
          : Column(
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
                            Text(
                                'Connected to ${connectedDevice!.platformName}'),
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
                            if (_receivedImage != null)
                              Image.memory(
                                _receivedImage!,
                                fit: BoxFit.cover,
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

void _saveImage(BuildContext context, _BleScreenState state) async {
  Position? userLocation;

  customLoadingOverlay();
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

  final response =
      await Api().uploadImage(state.imagePath!, latitude, longitude);
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
  } else {
    customSnackbar('Error', 'Failed to upload image');
  }
}

String randomString() {
  final random = Random.secure();
  final values = List<int>.generate(16, (i) => random.nextInt(255));
  return base64UrlEncode(values);
}

class ChatPage extends StatefulWidget {
  final String description;
  final String url;

  const ChatPage({
    super.key,
    required this.description,
    required this.url,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<types.Message> _messages = [];
  final List<String> _backendMessages = [];
  final RxBool isAnswerLoading = false.obs;

  late AudioPlayer sendPlayer, recceivePlayer;
  Duration? sendDuration, receiveDuration;

  final _user = const types.User(id: 'user');

  final TextEditingController mText = TextEditingController();
  final RxBool isMicOn = false.obs;

  @override
  void initState() {
    super.initState();
    sendPlayer = AudioPlayer();
    recceivePlayer = AudioPlayer();
    _initializeAudioPlayer();
  }

  Future<void> _initializeAudioPlayer() async {
    sendDuration = await sendPlayer.setAsset('assets/send_chime.mp3');
    receiveDuration = await recceivePlayer.setAsset('assets/recieve_chime.mp3');
  }

  @override
  void dispose() {
    sendPlayer.dispose();
    recceivePlayer.dispose();
    mText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SpeechToText speech = SpeechToText();

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Chat'),
          ),
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Description of image:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: SizedBox(
                  height: MediaQuery.of(context).size.width * 0.5,
                  child: SingleChildScrollView(
                    child: Text(
                      widget.description,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Ask any question',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Chat(
                  messages: _messages,
                  onSendPressed: handleSendPressed,
                  user: _user,
                  customBottomWidget: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 37, 35, 46),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.5),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: mText,
                              decoration: const InputDecoration(
                                hintText: 'Type a message',
                                hintStyle: TextStyle(color: Colors.white),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(0),
                              ),
                              style: const TextStyle(color: Colors.white),
                              onSubmitted: (value) async {
                                if (value.isNotEmpty) {
                                  final String text = mText.text;
                                  mText.clear();
                                  await handleSendPressed(
                                      types.PartialText(text: text));
                                }
                              },
                            ),
                          ),
                          Obx(() {
                            return IconButton(
                              icon: Icon(
                                Icons.mic,
                                semanticLabel: 'Microphone',
                                color:
                                    isMicOn.value ? Colors.red : Colors.white,
                              ),
                              onPressed: () async {
                                if (!isMicOn.value &&
                                    await speech.initialize()) {
                                  isMicOn.value = true;
                                  await speech.listen(
                                    onResult: (result) {
                                      mText.text = result.recognizedWords;
                                      isMicOn.value = false;
                                    },
                                  );
                                } else {
                                  isMicOn.value = false;
                                  speech.stop();
                                }
                              },
                            );
                          }),
                          IconButton(
                            icon: const Icon(
                              Icons.send,
                              semanticLabel: "Send",
                              color: Colors.white,
                            ),
                            onPressed: () async {
                              final String text = mText.text;
                              if (text.isNotEmpty) {
                                mText.clear();
                                await handleSendPressed(
                                    types.PartialText(text: text));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Obx(() => isAnswerLoading.value
            ? Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 20),
                      Text(
                        'Loading answer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          // background: Paint()..color = Colors.black,
                        ),
                      )
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink()),
      ],
    );
  }

  Future<void> handleSendPressed(types.PartialText message) async {
    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: randomString(),
      text: message.text,
    );

    final loadingMessage = types.TextMessage(
      author: const types.User(id: 'bot'),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: randomString(),
      text: 'Loading...',
    );

    setState(() {
      isAnswerLoading.value = true;
      _messages.insert(0, textMessage);
      _messages.insert(0, loadingMessage);
      _backendMessages.add(message.text);
    });

    final response = await Api()
        .getAnswer(message.text, widget.url, jsonEncode(_backendMessages));

    if (response != '') {
      final botMessage = types.TextMessage(
        author: const types.User(id: 'bot'),
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: randomString(),
        text: response,
        repliedMessage: textMessage,
      );
      setState(() {
        isAnswerLoading.value = false;
        _messages.removeAt(0);
        _messages.insert(0, botMessage);
      });
    }
  }
}

void customSnackbar(String title, String message) {
  Get.snackbar(
    title,
    message,
    snackPosition: SnackPosition.BOTTOM,
    backgroundColor: Colors.red,
    colorText: Colors.white,
    padding: const EdgeInsets.all(16),
  );
}

void customDialog(String title, String message) {
  Get.defaultDialog(
    title: title,
    middleText: message,
    backgroundColor: Colors.white,
    titleStyle: const TextStyle(color: Colors.black),
    middleTextStyle: const TextStyle(color: Colors.black),
    confirm: ElevatedButton(
      onPressed: () {
        Get.back();
        Get.back();
      },
      child: const Text('OK'),
    ),
  );
}

void customLoadingOverlay() {
  Get.dialog(
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.5),
    PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withOpacity(0.5),
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text(
                'Loading description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  // background: Paint()..color = Colors.black,
                ),
              )
            ],
          ),
        ),
      ),
    ),
  );
}
