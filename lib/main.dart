import 'package:flutter/material.dart';
import 'package:application/src/rust/frb_generated.dart';
import 'package:application/src/presentation/pages/connection_pairing_page.dart';
import 'package:application/src/features/pairing/data/http/http_signaling_backend.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'P2P Pairing',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: ConnectionPairingPage(
        signalingBaseUrl: 'http://127.0.0.1:8080',
        backend: HttpSignalingBackend('http://127.0.0.1:8080'),
      ),
    );
  }
}