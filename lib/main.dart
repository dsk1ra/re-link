import 'dart:async';

import 'package:flutter/material.dart';
import 'package:application/src/rust/frb_generated.dart';
import 'src/signaling/http_backend.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ChatPage());
  }
}
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _serverController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  HttpSignalingBackend? _backend;
  Timer? _pollTimer;
  String? _selfName;
  final List<_ChatEntry> _chat = []; // oldest first
  bool _connecting = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _backend?.dispose();
    _serverController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final addr = _serverController.text.trim();
    if (addr.isEmpty) return;
    if (!(addr.startsWith('http://') || addr.startsWith('https://'))) {
      _show('Enter full signaling base URL, e.g. http://127.0.0.1:8080');
      return;
    }
    setState(() => _connecting = true);
    try {
      final backend = HttpSignalingBackend(addr);
      final reg = await backend.register(deviceLabel: 'flutter-chat');
      _backend = backend;
      _selfName = reg.displayName;
  await _refreshChat();
  _startPolling();
      setState(() {});
    } catch (e) {
      _show('Connect failed: $e');
    } finally {
      setState(() => _connecting = false);
    }
  }

  Future<void> _refreshChat() async {
    if (_backend == null) return;
    final msgs = await _backend!.chatList();
    setState(() {
      _chat
        ..clear()
        ..addAll(msgs.map((m) => _ChatEntry(senderName: m.fromDisplayName, payload: m.text)));
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      try {
        if (_backend == null) return;
        await _refreshChat();
      } catch (_) {}
    });
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _backend == null) return;
    try {
      await _backend!.chatSend(text);
      _messageController.clear();
      await _refreshChat();
    } catch (e) {
      _show('Send failed: $e');
    }
  }

  Future<void> _disconnect() async {
    await _backend?.dispose();
    _backend = null;
    _pollTimer?.cancel();
    setState(() {
      _chat.clear();
      _selfName = null;
    });
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final connected = _backend?.isRegistered == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat Demo')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  if (!connected) ...[
                    Expanded(
                      child: TextField(
                        controller: _serverController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Signaling URL (http://host:port)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _connecting ? null : _connect,
                      child: Text(_connecting ? 'Connecting...' : 'Connect'),
                    ),
                  ] else ...[
                    Expanded(
                      child: Row(
                        children: [
                          Text('You: ${_selfName ?? ''}'),
                          const Spacer(),
                          IconButton(onPressed: _refreshChat, icon: const Icon(Icons.refresh)),
                          const SizedBox(width: 8),
                          ElevatedButton(onPressed: _disconnect, child: const Text('Disconnect')),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _chat.isEmpty
                  ? const Center(child: Text('No messages yet'))
                  : ListView.separated(
                      reverse: false,
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      itemCount: _chat.length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (context, index) {
                        final msg = _chat[index];
                        return ListTile(
                          dense: true,
                          title: Text(msg.payload),
                          subtitle: Text(msg.senderName),
                        );
                      },
                    ),
            ),
            if (connected)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Type a message'),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _send, child: const Text('Send')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatEntry {
  final String senderName;
  final String payload;
  _ChatEntry({required this.senderName, required this.payload});
}
