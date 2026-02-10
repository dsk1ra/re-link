import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:application/src/rust/frb_generated.dart';
import 'package:application/src/presentation/pages/connection_pairing_page.dart';
import 'package:application/src/features/pairing/data/http/http_signaling_backend.dart';

Future<void> main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    debugPrint(
      '${record.level.name}: ${record.time.toIso8601String()} '
      '${record.loggerName}: ${record.message}',
    );
    if (record.error != null) {
      debugPrint('Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      debugPrint(record.stackTrace.toString());
    }
  });
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
        ),
        scaffoldBackgroundColor: const Color(0xFFd8cbc7),
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
      home: const _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    // defined via --dart-define=SIGNALING_URL=... or --dart-define-from-file=client/config/dev.json
    const signalingUrl = String.fromEnvironment(
      'SIGNALING_URL',
      defaultValue: 'http://localhost:8080',
    );

    return ConnectionPairingPage(
      signalingBaseUrl: signalingUrl,
      backend: HttpSignalingBackend(signalingUrl),
    );
  }
}
