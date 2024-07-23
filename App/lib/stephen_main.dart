import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: HotspotScreen(),
    );
  }
}

class HotspotScreen extends StatefulWidget {
  const HotspotScreen({super.key});

  @override
  _HotspotScreenState createState() => _HotspotScreenState();
}

class _HotspotScreenState extends State<HotspotScreen> {
  static const platform = MethodChannel('com.example.iotascamapp/hotspot');

  String _ssid = 'Not set';
  String _password = 'Not set';

  Future<void> _startHotspot() async {
    try {
      final result = await platform.invokeMethod('startHotspot');
      setState(() {
        _ssid = result['ssid'];
        _password = result['password'];
        print('SSID: $_ssid, Password: $_password');
      });
    } on PlatformException catch (e) {
      print("Failed to start hotspot: '${e.message}'.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hotspot Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('SSID: $_ssid'),
            Text('Password: $_password'),
            ElevatedButton(
              onPressed: _startHotspot,
              child: const Text('Start Hotspot'),
            ),
          ],
        ),
      ),
    );
  }
}
