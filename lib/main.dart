import 'dart:async';

import 'package:flutter/material.dart';
import 'package:application/src/rust/frb_generated.dart';
import 'package:application/src/features/pairing/data/http/http_signaling_backend.dart';
import 'package:application/src/presentation/widgets/handshake_card.dart';
import 'package:application/src/presentation/widgets/room_info.dart';

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
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _roomPasswordController = TextEditingController();

  HttpSignalingBackend? _backend;
  String? _selfName;
  bool _connecting = false;
  String? _connectError;

  // Handshake (room) creation/join state
  String? _createdRoomId;
  String? _createdRoomPassword;
  String? _createdInitiatorToken;
  int? _roomTtlRemaining; // seconds
  Timer? _roomTtlTimer;
  Timer? _statusPollTimer;
  bool _roomConnected = false;

  String? _joinedInitiatorToken;
  String? _joinedReceiverToken;
  String? _lastRoomId; // room connected (created or joined)
  bool? _isInitiator; // true if created, false if joined

  // The app auto-connects on launch to this signaling server.
  // To change the target, update this constant or make it configurable elsewhere.
  static const String _serverUrl = 'http://127.0.0.1:8080';

  @override
  void initState() {
    super.initState();
    // Auto-connect to the fixed server as soon as the page loads.
    // A short microtask ensures build has a context for SnackBars if needed.
    scheduleMicrotask(() {
      _connect();
    });
  }

  @override
  void dispose() {
    _backend?.dispose();
    _roomIdController.dispose();
    _roomPasswordController.dispose();
    _roomTtlTimer?.cancel();
    _statusPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    try {
      final backend = HttpSignalingBackend(_serverUrl);
      final reg = await backend.register(deviceLabel: 'flutter-pairing');
      _backend = backend;
      _selfName = reg.displayName;
      setState(() {});
    } catch (e) {
      _connectError = e.toString();
      _show('Connect failed: $e');
    } finally {
      setState(() => _connecting = false);
    }
  }

  Future<void> _createRoom() async {
    if (_backend == null || !_backend!.isRegistered) {
      _show('Not connected to server');
      return;
    }
    try {
      final resp = await _backend!.roomCreate();
      setState(() {
        _createdRoomId = resp.roomId;
        _createdRoomPassword = resp.password;
        _createdInitiatorToken = resp.initiatorToken;
        _joinedInitiatorToken = null;
        _joinedReceiverToken = null;
        _roomTtlRemaining = resp.ttlSeconds ?? 30;
        _lastRoomId = resp.roomId;
        _isInitiator = true;
        _roomConnected = false;
      });
      _roomTtlTimer?.cancel();
      _statusPollTimer?.cancel();
      if (_roomTtlRemaining != null) {
        _roomTtlTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) return;
          setState(() {
            if (_roomTtlRemaining != null && _roomTtlRemaining! > 0) {
              _roomTtlRemaining = _roomTtlRemaining! - 1;
            } else {
              t.cancel();
            }
          });
        });
        _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
          if (!mounted) return;
          final roomId = _createdRoomId;
          if (roomId == null || _backend == null) return;
          try {
            final result = await _backend!.roomStatus(roomId);
            final status = result.$1;
            final ttl = result.$2;
            if (status == 'joined') {
              _roomTtlTimer?.cancel();
              _statusPollTimer?.cancel();
              setState(() {
                _roomConnected = true;
                _roomTtlRemaining = null;
              });
            } else if (status == 'expired' || (ttl != null && ttl <= 0)) {
              _roomTtlTimer?.cancel();
              _statusPollTimer?.cancel();
              await _createRoom();
            } else if (ttl != null) {
              setState(() {
                _roomTtlRemaining = ttl;
              });
            }
          } catch (_) {
            // ignore transient errors
          }
        });
      }
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
    if (_backend == null || !_backend!.isRegistered) {
      _show('Not connected to server');
      return;
    }
    try {
      final resp = await _backend!.roomJoin(roomId: roomId, password: password);
      setState(() {
        _joinedInitiatorToken = resp.initiatorToken;
        _joinedReceiverToken = resp.receiverToken;
        // When someone joins, server deletes the room. Invalidate local countdown.
        _roomTtlTimer?.cancel();
        _roomTtlRemaining = null;
        _lastRoomId = roomId;
        _isInitiator = false;
        _roomConnected = true;
      });
    } catch (e) {
      _show('Join room failed: $e');
    }
  }

  void _resetHandshakeState() {
    setState(() {
      _createdRoomId = null;
      _createdRoomPassword = null;
      _createdInitiatorToken = null;
      _joinedInitiatorToken = null;
      _joinedReceiverToken = null;
      _roomTtlTimer?.cancel();
      _statusPollTimer?.cancel();
      _roomTtlRemaining = null;
      _roomIdController.clear();
      _roomPasswordController.clear();
      _lastRoomId = null;
      _isInitiator = null;
      _roomConnected = false;
    });
  }

  Future<void> _disconnect() async {
    await _backend?.dispose();
    _backend = null;
    setState(() {
      _selfName = null;
    });
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final connected = _backend?.isRegistered == true;
    final hasRoom = (_createdRoomId != null) || (_joinedInitiatorToken != null && _joinedReceiverToken != null);
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
                              Text('You: ${_selfName ?? ''}') ,
                              const Spacer(),
                              ElevatedButton(onPressed: _disconnect, child: const Text('Disconnect')),
                            ],
                          )
                        : Row(
                            children: [
                              if (_connecting) ...[
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
                                    _connectError != null
                                        ? 'Failed to connect: $_connectError'
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
                          roleIsInitiator: _isInitiator == true,
                          roomId: _lastRoomId,
                          ttlRemaining: _isInitiator == true && !_roomConnected ? _roomTtlRemaining : null,
                          initiatorToken: _isInitiator == true ? _createdInitiatorToken : _joinedInitiatorToken,
                          receiverToken: _isInitiator == true ? null : _joinedReceiverToken,
                          password: _isInitiator == true ? _createdRoomPassword : null,
              connected: _roomConnected,
                          onReset: _resetHandshakeState,
                        )
                      : HandshakeCard(
                          connected: connected,
                          ttlRemaining: _roomTtlRemaining,
                          createdRoomId: _createdRoomId,
                          createdRoomPassword: _createdRoomPassword,
                          createdInitiatorToken: _createdInitiatorToken,
                          joinedInitiatorToken: _joinedInitiatorToken,
                          joinedReceiverToken: _joinedReceiverToken,
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

// Widgets moved to presentation/widgets: HandshakeCard, RoomInfo, KvRow
