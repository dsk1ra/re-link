import 'dart:async';

import 'package:flutter/material.dart';
import 'package:application/src/features/pairing/data/http/http_signaling_backend.dart';
import 'package:application/src/features/pairing/application/pairing_controller.dart';
import 'package:application/src/presentation/widgets/handshake_card.dart';
import 'package:application/src/presentation/widgets/room_info.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _roomPasswordController = TextEditingController();

  PairingController? _controller;

  // The app auto-connects on launch to this signaling server.
  // To change the target, update this constant or make it configurable elsewhere.
  static const String _serverUrl = 'http://127.0.0.1:8080';

  @override
  void initState() {
    super.initState();
    // Create controller and auto-connect.
    final c = PairingController(HttpSignalingBackend(_serverUrl));
    c.addListener(() {
      if (mounted) setState(() {});
    });
    _controller = c;
    scheduleMicrotask(() => _connect());
  }

  @override
  void dispose() {
    _controller?.dispose();
    _roomIdController.dispose();
    _roomPasswordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      await _controller?.connect(deviceLabel: 'flutter-pairing');
    } catch (e) {
      _show('Connect failed: $e');
    }
  }

  Future<void> _createRoom() async {
    if (_controller == null || !_controller!.isRegistered) {
      _show('Not connected to server');
      return;
    }
    try {
      await _controller!.createRoom();
    } catch (e) {
      _show('Create room failed: $e');
    }
  }

  Future<void> _joinRoom() async {
    final roomId = _roomIdController.text.trim();
    final password = _roomPasswordController.text.trim();
    if (roomId.isEmpty || password.isEmpty) {
      _show('Enter Room ID and Password');
      return;
    }
    if (_controller == null || !_controller!.isRegistered) {
      _show('Not connected to server');
      return;
    }
    try {
      await _controller!.joinRoom(roomId: roomId, password: password);
    } catch (e) {
      _show('Join room failed: $e');
    }
  }

  void _resetHandshakeState() {
    _controller?.resetHandshake();
    _roomIdController.clear();
    _roomPasswordController.clear();
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final connected = c?.isRegistered == true;
    final hasRoom = (c?.createdRoomId != null) || (c?.joinedInitiatorToken != null && c?.joinedReceiverToken != null);
    return Scaffold(
      appBar: AppBar(title: const Text('Pairing Screen')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: connected
                        ? Row(
                            children: [
                              Text('You: ${c?.displayName ?? ''}') ,
                            ],
                          )
                        : Row(
                            children: [
                              if (c?.isConnecting == true) ...[
                                const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 12),
                                const Text('Connecting to the server...'),
                                const SizedBox(width: 8),
                                Text(
                                  _serverUrl,
                                  style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                                ),
                              ] else ...[
                                const Icon(Icons.cloud_off, color: Colors.redAccent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    c?.connectError != null
                                        ? 'Failed to connect: ${c?.connectError}'
                                        : 'Not connected',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(onPressed: _connect, child: const Text('Retry')),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
            if (connected)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: hasRoom
            ? RoomInfo(
                          roleIsInitiator: c?.isInitiator == true,
                          roomId: c?.lastRoomId,
                          ttlRemaining: c?.isInitiator == true && !(c?.roomConnected ?? false) ? c?.roomTtlRemaining : null,
                          initiatorToken: c?.isInitiator == true ? c?.createdInitiatorToken : c?.joinedInitiatorToken,
                          receiverToken: c?.isInitiator == true ? null : c?.joinedReceiverToken,
                          password: c?.isInitiator == true ? c?.createdRoomPassword : null,
              connected: c?.roomConnected ?? false,
                          onReset: _resetHandshakeState,
                        )
                      : HandshakeCard(
                          connected: connected,
                          ttlRemaining: c?.roomTtlRemaining,
                          createdRoomId: c?.createdRoomId,
                          createdRoomPassword: c?.createdRoomPassword,
                          createdInitiatorToken: c?.createdInitiatorToken,
                          joinedInitiatorToken: c?.joinedInitiatorToken,
                          joinedReceiverToken: c?.joinedReceiverToken,
                          onCreateRoom: _createRoom,
                          onJoinRoom: _joinRoom,
                          roomIdController: _roomIdController,
                          roomPasswordController: _roomPasswordController,
                          onReset: _resetHandshakeState,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
