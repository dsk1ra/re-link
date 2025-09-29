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

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _messages = <String>[]; // newest first, capped at 10

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? _]) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    // Call into Rust to produce the message. Rust manages the buffer.
    greet(name: text);

    // Refresh the local view of the buffer by asking Rust for the list.
    final joined = greet(name: '__list__');
    setState(() {
      if (joined.isEmpty) {
        _messages.clear();
      } else {
        _messages
          ..clear()
          ..addAll(joined.split('|||'));
      }
    });

    // Clear the input field (flush it) after submitting.
    _controller.clear();
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
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Enter Your Message',
                      ),
                      onSubmitted: _submit,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Submit'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      // Ask Rust to consume the newest item, then refresh the list.
                      greet(name: '__consume__');
                      final joined = greet(name: '__list__');
                      setState(() {
                        if (joined.isEmpty) {
                          _messages.clear();
                        } else {
                          _messages
                            ..clear()
                            ..addAll(joined.split('|||'));
                        }
                      });
                    },
                    child: const Text('Consume'),
                  ),
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
