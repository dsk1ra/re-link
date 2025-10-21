import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../pairing/domain/models.dart';
import '../../pairing/domain/signaling_backend.dart';

/// Orchestrates registration and ephemeral room handshake state.
/// Owns TTL countdown and status polling timers; emits changes via ChangeNotifier.
class PairingController extends ChangeNotifier {
  final SignalingBackend _backend;

  PairingController(this._backend);

  // Connection state
  bool _connecting = false;
  String? _connectError;

  bool get isRegistered => _backend.isRegistered;
  bool get isConnecting => _connecting;
  String? get connectError => _connectError;
  String? get displayName => _backend.displayName;

  // Handshake (room) creation/join state
  String? createdRoomId;
  String? createdRoomPassword;
  String? createdInitiatorToken;
  int? roomTtlRemaining; // seconds
  bool roomConnected = false;

  String? joinedInitiatorToken;
  String? joinedReceiverToken;
  String? lastRoomId; // room connected (created or joined)
  bool? isInitiator; // true if created, false if joined

  Timer? _roomTtlTimer;
  Timer? _statusPollTimer;

  Future<void> connect({required String deviceLabel}) async {
    _connecting = true;
    _connectError = null;
    notifyListeners();
    try {
      await _backend.register(deviceLabel: deviceLabel);
    } catch (e) {
      _connectError = e.toString();
      rethrow;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _backend.dispose();
    _clearHandshakeState();
    _connectError = null;
    notifyListeners();
  }

  Future<CreateRoomResponse> createRoom() async {
    if (!_backend.isRegistered) {
      throw StateError('Not connected to server');
    }
    final resp = await _backend.roomCreate();
    createdRoomId = resp.roomId;
    createdRoomPassword = resp.password;
    createdInitiatorToken = resp.initiatorToken;
    joinedInitiatorToken = null;
    joinedReceiverToken = null;
    roomTtlRemaining = resp.ttlSeconds ?? 30;
    lastRoomId = resp.roomId;
    isInitiator = true;
    roomConnected = false;
    _startTtlCountdown();
    _startStatusPolling();
    notifyListeners();
    return resp;
  }

  Future<JoinRoomResponse> joinRoom({required String roomId, required String password}) async {
    if (!_backend.isRegistered) {
      throw StateError('Not connected to server');
    }
    final resp = await _backend.roomJoin(roomId: roomId, password: password);
    joinedInitiatorToken = resp.initiatorToken;
    joinedReceiverToken = resp.receiverToken;
    _cancelTtl();
    roomTtlRemaining = null;
    lastRoomId = roomId;
    isInitiator = false;
    roomConnected = true;
    _cancelStatusPolling();
    notifyListeners();
    return resp;
  }

  void resetHandshake() {
    _clearHandshakeState();
    notifyListeners();
  }

  void _clearHandshakeState() {
    createdRoomId = null;
    createdRoomPassword = null;
    createdInitiatorToken = null;
    joinedInitiatorToken = null;
    joinedReceiverToken = null;
    _cancelTtl();
    _cancelStatusPolling();
    roomTtlRemaining = null;
    lastRoomId = null;
    isInitiator = null;
    roomConnected = false;
  }

  void _startTtlCountdown() {
    _cancelTtl();
    if (roomTtlRemaining != null) {
      _roomTtlTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (roomTtlRemaining != null && roomTtlRemaining! > 0) {
          roomTtlRemaining = roomTtlRemaining! - 1;
          notifyListeners();
        } else {
          t.cancel();
        }
      });
    }
  }

  void _cancelTtl() {
    _roomTtlTimer?.cancel();
    _roomTtlTimer = null;
  }

  void _startStatusPolling() {
    _cancelStatusPolling();
    final roomId = createdRoomId;
    if (roomId == null) return;
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      try {
        final result = await _backend.roomStatus(roomId);
        final status = result.$1;
        final ttl = result.$2;
        if (status == 'joined') {
          _cancelTtl();
          _cancelStatusPolling();
          roomConnected = true;
          roomTtlRemaining = null;
          notifyListeners();
        } else if (status == 'expired' || (ttl != null && ttl <= 0)) {
          _cancelTtl();
          _cancelStatusPolling();
          // automatically try to create a new room
          await createRoom();
        } else if (ttl != null) {
          roomTtlRemaining = ttl;
          notifyListeners();
        }
      } catch (_) {
        // ignore transient errors
      }
    });
  }

  void _cancelStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
  }

  @override
  void dispose() {
    _cancelTtl();
    _cancelStatusPolling();
    super.dispose();
  }
}
