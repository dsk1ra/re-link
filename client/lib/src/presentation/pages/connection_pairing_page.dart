import 'dart:async';

import 'package:flutter/material.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/presentation/pages/initiator_page.dart';
import 'package:application/src/presentation/pages/responder_page.dart';

/// Main launcher page for P2P connection
class ConnectionPairingPage extends StatefulWidget {
  final String signalingBaseUrl;
  final SignalingBackend backend;

  const ConnectionPairingPage({
    super.key,
    this.signalingBaseUrl = 'http://127.0.0.1:8080',
    required this.backend,
  });

  @override
  State<ConnectionPairingPage> createState() => _ConnectionPairingPageState();
}

class _ConnectionPairingPageState extends State<ConnectionPairingPage> {
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() => _connectToServer());
  }

  @override
  void dispose() {
    widget.backend.dispose();
    super.dispose();
  }

  Future<void> _connectToServer() async {
    setState(() {
      _connecting = true;
    });

    try {
      await widget.backend.register(deviceLabel: 'Flutter P2P Client');
      setState(() => _connecting = false);
    } catch (e) {
      setState(() {
        _connecting = false;
      });
      _showSnackBar('Connection failed: $e');
    }
  }

  void _navigateToInitiator() {
    if (!widget.backend.isRegistered) {
      _showSnackBar('Not connected to server');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InitiatorPage(
          signalingBaseUrl: widget.signalingBaseUrl,
          backend: widget.backend,
        ),
      ),
    );
  }

  void _navigateToResponder() {
    if (!widget.backend.isRegistered) {
      _showSnackBar('Not connected to server');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResponderPage(
          signalingBaseUrl: widget.signalingBaseUrl,
          backend: widget.backend,
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.backend.isRegistered;

    return Scaffold(
      backgroundColor: const Color(0xFFd8cbc7),
      appBar: AppBar(
        title: const Text(
          'P2P Connect',
          style: TextStyle(color: Color(0xFFffffff)),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF19231a),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Connection status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: connected
                ? const Color(0xFF19231a)
                : (_connecting
                      ? const Color(0xFFcc3f0c)
                      : const Color(0xFF19231a).withAlpha(179)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_connecting) ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFffffff),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Connecting to server...',
                    style: TextStyle(color: Color(0xFFffffff)),
                  ),
                ] else if (connected) ...[
                  Text(
                    widget.backend.displayName ?? 'Connected to server',
                    style: const TextStyle(
                      color: Color(0xFFffffff),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Not connected',
                    style: TextStyle(color: Color(0xFFffffff)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _connectToServer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFd8cbc7),
                      foregroundColor: const Color(0xFF19231a),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),

          // Main options
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),
                    const Text(
                      'Peer-to-Peer Connection',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF19231a),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Secure, direct connection with minimal server involvement',
                      style: TextStyle(fontSize: 14, color: Color(0xFF19231a)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Create Connection button
                    SizedBox(
                      width: 300,
                      child: Card(
                        elevation: 2,
                        color: const Color(0xFFffffff),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: connected
                                ? const Color(0xFFcc3f0c)
                                : const Color(0xFF19231a).withAlpha(77),
                            width: 2,
                          ),
                        ),
                        child: InkWell(
                          onTap: connected ? _navigateToInitiator : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Text(
                                  'Create Connection',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: connected
                                        ? const Color(0xFF19231a)
                                        : const Color(
                                            0xFF19231a,
                                          ).withAlpha(102),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Generate a link to share',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: connected
                                        ? const Color(0xFF19231a).withAlpha(179)
                                        : const Color(0xFF19231a).withAlpha(77),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'OR',
                      style: TextStyle(
                        color: Color(0xFF19231a),
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Join Connection button
                    SizedBox(
                      width: 300,
                      child: Card(
                        elevation: 2,
                        color: const Color(0xFFffffff),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: connected
                                ? const Color(0xFFcc3f0c)
                                : const Color(0xFF19231a).withAlpha(77),
                            width: 2,
                          ),
                        ),
                        child: InkWell(
                          onTap: connected ? _navigateToResponder : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Text(
                                  'Join Connection',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: connected
                                        ? const Color(0xFF19231a)
                                        : const Color(
                                            0xFF19231a,
                                          ).withAlpha(102),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Use a shared link',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: connected
                                        ? const Color(0xFF19231a).withAlpha(179)
                                        : const Color(0xFF19231a).withAlpha(77),
                                  ),
                                  textAlign: TextAlign.center,
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
            ),
          ),
        ],
      ),
    );
  }
}
