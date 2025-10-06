import 'dart:async';

import 'package:flutter/material.dart';
import 'package:application/src/rust/frb_generated.dart';
import 'src/signaling/signaling_client.dart';
import 'src/messaging/message_queue_backend.dart';
import 'src/messaging/http_queue_backend.dart';

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

/// HTTP signaling client that sends messages to itself.
/// Expose minimal produce/list 
// Message queue abstraction instance in UI
typedef Backend = MessageQueueBackend;

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _serverController = TextEditingController();
  final List<String> _messages = <String>[]; // newest first

  Backend? _backend;
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
      if (!(addr.startsWith('http://') || addr.startsWith('https://'))) {
        throw Exception('Enter full signaling base URL, e.g. http://127.0.0.1:8080');
      }
      final signaling = SignalingClient(addr);
      await signaling.register(deviceLabel: 'flutter-app');
      final queue = HttpQueueBackend(
        baseUrl: addr,
        clientId: signaling.clientId!,
        sessionToken: signaling.sessionToken!,
      );
      _backend = _HttpQueueAdapter(queue);

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
                          labelText: 'Enter signaling base URL (http://host:port)',
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
                          labelText: 'Enter message to send to self',
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
                      child: const Text('Consume (just polls again)'),
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

class _HttpQueueAdapter implements MessageQueueBackend {
  final HttpQueueBackend inner;
  _HttpQueueAdapter(this.inner);

  @override
  Future<void> dispose() => inner.dispose();

  @override
  Future<List<String>> list() async {
    final items = await inner.list();
    // newest first is not guaranteed by server; just return as-is for now
    return items.reversed.toList();
  }

  @override
  Future<void> produce(String payload) => inner.produce(payload);

  @override
  Future<String?> consume() => inner.consume();
}
