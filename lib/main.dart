import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:application/src/rust/api/simple.dart';
import 'package:application/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: MainPage());
  }
}

/// Abstract backend that can produce, consume, list messages and be disposed
abstract class ServerBackend {
  Future<void> produce(String name);

  Future<String?> consume();

  Future<List<String>> list();

  Future<void> dispose();
}

/// Local Rust backend that routes through flutter_rust_bridge using special tokens
class LocalRustBackend implements ServerBackend {
  LocalRustBackend();

  @override
  Future<void> produce(String name) async {
    // produce via greet(name)
    greet(name: name);
  }

  @override
  Future<String?> consume() async {
    final res = greet(name: '__consume__');
    return res.isEmpty ? null : res;
  }

  @override
  Future<List<String>> list() async {
    final joined = greet(name: '__list__');
    if (joined.isEmpty) return [];
    return joined.split('|||');
  }

  @override
  Future<void> dispose() async {}
}

/// TCP backend: simple line protocol for demo purposes.
/// Commands:
/// PRODUCE:<name> -> reply OK
/// CONSUME -> reply with consumed line or empty
/// LIST -> reply with joined messages via |||
class TcpBackend implements ServerBackend {
  Socket? _socket;
  final _readController = StreamController<String>();
  StreamSubscription<String>? _sub;

  Future<void> connect(String host, int port) async {
    _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
    _sub = _socket!.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      _readController.add(line);
    });
  }

  Future<void> _sendLine(String line) async {
    if (_socket == null) throw Exception('Not connected');
    _socket!.write('$line\n');
    await _socket!.flush();
  }

  Future<String> _readOne({Duration timeout = const Duration(seconds: 2)}) async {
    return _readController.stream.first.timeout(timeout);
  }

  @override
  Future<void> produce(String name) async {
    await _sendLine('PRODUCE:$name');
    final r = await _readOne();
    if (r != 'OK') throw Exception('Produce failed: $r');
  }

  @override
  Future<String?> consume() async {
    await _sendLine('CONSUME');
    final r = await _readOne();
    return r.isEmpty ? null : r;
  }

  @override
  Future<List<String>> list() async {
    await _sendLine('LIST');
    final r = await _readOne();
    if (r.isEmpty) return [];
    return r.split('|||');
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _socket?.close();
    await _readController.close();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _serverController = TextEditingController();
  final List<String> _messages = <String>[]; // newest first

  ServerBackend? _backend;
  bool _connected = false;
  bool _connecting = false;

  @override
  void dispose() {
    _controller.dispose();
    _serverController.dispose();
    _backend?.dispose();
    super.dispose();
  }

  Future<void> _connect(String addr) async {
    setState(() {
      _connecting = true;
    });

    try {
      if (addr == 'local') {
        _backend = LocalRustBackend();
      } else {
        final parts = addr.split(':');
        final host = parts[0];
        final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 4000 : 4000;
        final tcp = TcpBackend();
        await tcp.connect(host, port);
        _backend = tcp;
      }

      final list = await _backend!.list();
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _connected = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connect failed: $e')));
    } finally {
      setState(() {
        _connecting = false;
      });
    }
  }

  Future<void> _produce(String text) async {
    if (!_connected || _backend == null) return;
    await _backend!.produce(text);
    final list = await _backend!.list();
    setState(() {
      _messages
        ..clear()
        ..addAll(list);
    });
  }

  Future<void> _consume() async {
    if (!_connected || _backend == null) return;
    await _backend!.consume();
    final list = await _backend!.list();
    setState(() {
      _messages
        ..clear()
        ..addAll(list);
    });
  }

  Future<void> _disconnect() async {
    await _backend?.dispose();
    _backend = null;
    setState(() {
      _connected = false;
      _messages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Main Page')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  if (!_connected) ...[
                    Expanded(
                      child: TextField(
                        controller: _serverController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Enter Rust server address (host:port or "local")',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _connecting
                          ? null
                          : () async {
                              final addr = _serverController.text.trim();
                              if (addr.isEmpty) return;
                              await _connect(addr);
                            },
                      child: _connecting ? const Text('Connecting...') : const Text('Connect'),
                    ),
                  ] else ...[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Enter Your Message',
                        ),
                        onSubmitted: (v) => _produce(v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _produce(_controller.text.trim()),
                      child: const Text('Submit'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _consume,
                      child: const Text('Consume'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _disconnect,
                      child: const Text('Disconnect'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text('Result will appear here'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      itemCount: _messages.length,
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return ListTile(
                          dense: true,
                          title: Text(msg),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
