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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFcc3f0c),
          primary: const Color(0xFF19231a),
          secondary: const Color(0xFFcc3f0c),
          surface: const Color(0xFFd8cbc7),
          background: const Color(0xFFd8cbc7),
        ),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFcc3f0c),
            foregroundColor: const Color(0xFFffffff),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF19231a)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: const OutlineInputBorder(),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF19231a)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFcc3f0c), width: 2),
          ),
          labelStyle: const TextStyle(color: Color(0xFF19231a)),
          prefixIconColor: const Color(0xFF19231a),
          filled: true,
          fillColor: const Color(0xFFffffff),
        ),
      ),
      home: ConnectionPairingPage(
        signalingBaseUrl: 'http://127.0.0.1:8080',
        backend: HttpSignalingBackend('http://127.0.0.1:8080'),
      ),
    );
  }
}
