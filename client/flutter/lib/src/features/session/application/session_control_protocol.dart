import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

typedef SessionMessageSender = Future<void> Function(String message);
typedef SessionDescriptionHandler =
    Future<void> Function(RTCSessionDescription description);
typedef SessionIceCandidateHandler =
    Future<void> Function(RTCIceCandidate candidate);
typedef SessionAsyncCallback = Future<void> Function();
typedef SessionMessageCallback = void Function(String message);

class SessionControlProtocol {
  SessionControlProtocol({
    required Logger log,
    required SessionMessageSender sendControlMessage,
    required SessionDescriptionHandler onRenegotiationOffer,
    required SessionDescriptionHandler onRenegotiationAnswer,
    required SessionIceCandidateHandler onIceCandidate,
    required SessionAsyncCallback onPeerSessionClosed,
    required VoidCallback onScreenShareStopped,
    required SessionMessageCallback showMessage,
  }) : _log = log,
       _sendControlMessage = sendControlMessage,
       _onRenegotiationOffer = onRenegotiationOffer,
       _onRenegotiationAnswer = onRenegotiationAnswer,
       _onIceCandidate = onIceCandidate,
       _onPeerSessionClosed = onPeerSessionClosed,
       _onScreenShareStopped = onScreenShareStopped,
       _showMessage = showMessage;

  final Logger _log;
  final SessionMessageSender _sendControlMessage;
  final SessionDescriptionHandler _onRenegotiationOffer;
  final SessionDescriptionHandler _onRenegotiationAnswer;
  final SessionIceCandidateHandler _onIceCandidate;
  final SessionAsyncCallback _onPeerSessionClosed;
  final VoidCallback _onScreenShareStopped;
  final SessionMessageCallback _showMessage;

  Timer? _heartbeatTimer;
  Timer? _sessionClosedAckTimer;
  DateTime? _lastPongAt;
  String? _sessionClosedId;
  bool _sessionClosedAcked = false;

  Future<void> handleMessage(String message) async {
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final type = decoded['type'];
      if (type == 'session_closed') {
        await _sendSessionClosedAck(decoded['id']?.toString());
        await _onPeerSessionClosed();
        return;
      }
      if (type == 'session_closed_ack') {
        _handleSessionClosedAck(decoded['id']?.toString());
        return;
      }
      if (type == 'ping') {
        await _sendPong(decoded['ts']?.toString());
        return;
      }
      if (type == 'pong') {
        _lastPongAt = DateTime.now();
        return;
      }
      if (type == 'webrtc_offer') {
        final data = (decoded['data'] as Map).cast<String, dynamic>();
        final offer = RTCSessionDescription(
          data['sdp'] as String,
          data['type'] as String,
        );
        await _onRenegotiationOffer(offer);
        return;
      }
      if (type == 'webrtc_answer') {
        final data = (decoded['data'] as Map).cast<String, dynamic>();
        final answer = RTCSessionDescription(
          data['sdp'] as String,
          data['type'] as String,
        );
        await _onRenegotiationAnswer(answer);
        return;
      }
      if (type == 'webrtc_ice') {
        final data = (decoded['data'] as Map).cast<String, dynamic>();
        final candidate = RTCIceCandidate(
          data['candidate'] as String,
          data['sdpMid'] as String?,
          data['sdpMLineIndex'] as int?,
        );
        await _onIceCandidate(candidate);
        return;
      }
      if (type == 'screen_share_stopped') {
        _onScreenShareStopped();
        return;
      }
    } catch (_) {}

    _showMessage('Received: $message');
  }

  Future<void> sendSessionClosedMessage() async {
    try {
      _sessionClosedId = DateTime.now().millisecondsSinceEpoch.toString();
      _sessionClosedAcked = false;
      _startSessionClosedAckTimer();
      final msg = jsonEncode({
        'type': 'session_closed',
        'id': _sessionClosedId,
        'reason': 'local_disconnect',
      });
      await _sendControlMessage(msg);
    } catch (e) {
      _log.warning('Error sending session closed message: $e');
    }
  }

  void startHeartbeat() {
    stopHeartbeat();
    _lastPongAt = DateTime.now();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final last = _lastPongAt;
      if (last != null &&
          DateTime.now().difference(last) > const Duration(seconds: 15)) {
        _handleHeartbeatTimeout();
        return;
      }

      unawaited(_sendPing());
    });
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void dispose() {
    stopHeartbeat();
    _sessionClosedAckTimer?.cancel();
    _sessionClosedAckTimer = null;
  }

  void _handleHeartbeatTimeout() {
    _log.warning('Heartbeat timeout, closing session');
    stopHeartbeat();
    unawaited(_onPeerSessionClosed());
  }

  Future<void> _sendPing() async {
    try {
      final msg = jsonEncode({
        'type': 'ping',
        'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      await _sendControlMessage(msg);
    } catch (e) {
      _log.warning('Error sending ping: $e');
    }
  }

  Future<void> _sendPong(String? ts) async {
    try {
      final msg = jsonEncode({'type': 'pong', 'ts': ts});
      await _sendControlMessage(msg);
    } catch (e) {
      _log.warning('Error sending pong: $e');
    }
  }

  void _startSessionClosedAckTimer() {
    _sessionClosedAckTimer?.cancel();
    _sessionClosedAckTimer = Timer(const Duration(seconds: 5), () {
      if (_sessionClosedAcked) return;
      _log.warning('Session closed ack not received');
    });
  }

  void _handleSessionClosedAck(String? id) {
    if (_sessionClosedId == null || _sessionClosedId != id) return;
    _sessionClosedAcked = true;
    _sessionClosedAckTimer?.cancel();
  }

  Future<void> _sendSessionClosedAck(String? id) async {
    if (id == null) return;
    try {
      final msg = jsonEncode({'type': 'session_closed_ack', 'id': id});
      await _sendControlMessage(msg);
    } catch (e) {
      _log.warning('Error sending session closed ack: $e');
    }
  }
}
