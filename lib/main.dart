import 'package:flutter/material.dart';
import 'package:application/src/rust/frb_generated.dart';
import 'package:application/src/presentation/pages/pairing_page.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: PairingPage());
  }
}