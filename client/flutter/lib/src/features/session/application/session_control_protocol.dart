import 'dart:async';

import 'package:logging/logging.dart';

typedef SessionPingSender = Future<void> Function(String ts);
typedef SessionClosedSender =
    Future<void> Function({required String id, String? reason});
typedef SessionAsyncCallback = Future<void> Function();
typedef SessionNowProvider = DateTime Function();

class SessionControlProtocol {
  SessionControlProtocol({
    required Logger log,
    required SessionPingSender sendPing,
    required SessionClosedSender sendSessionClosed,
    required SessionAsyncCallback onHeartbeatTimeout,
    SessionNowProvider? nowProvider,
  }) : _log = log,
       _sendPing = sendPing,
       _sendSessionClosed = sendSessionClosed,
       _onHeartbeatTimeout = onHeartbeatTimeout,
       _nowProvider = nowProvider ?? DateTime.now;

  final Logger _log;
  final SessionPingSender _sendPing;
  final SessionClosedSender _sendSessionClosed;
  final SessionAsyncCallback _onHeartbeatTimeout;
  final SessionNowProvider _nowProvider;

  Timer? _heartbeatTimer;
  Timer? _sessionClosedAckTimer;
  DateTime? _lastPongAt;
  String? _sessionClosedId;
  bool _sessionClosedAcked = false;

  void startHeartbeat() {
    stopHeartbeat();
    _lastPongAt = _nowProvider();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final last = _lastPongAt;
      if (last != null &&
          _nowProvider().difference(last) > const Duration(seconds: 15)) {
        _handleHeartbeatTimeout();
        return;
      }

      unawaited(_sendPing(_nowProvider().millisecondsSinceEpoch.toString()));
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

  void handlePong() {
    _lastPongAt = _nowProvider();
  }

  void handleSessionClosedAck(String? id) {
    if (_sessionClosedId == null || _sessionClosedId != id) return;
    _sessionClosedAcked = true;
    _sessionClosedAckTimer?.cancel();
  }

  Future<void> sendSessionClosedMessage() async {
    try {
      _sessionClosedId = _nowProvider().millisecondsSinceEpoch.toString();
      _sessionClosedAcked = false;
      _startSessionClosedAckTimer();
      await _sendSessionClosed(
        id: _sessionClosedId!,
        reason: 'local_disconnect',
      );
    } catch (_) {
      _log.warning('Session close message failed');
    }
  }

  void _handleHeartbeatTimeout() {
    _log.warning('Session heartbeat timed out');
    stopHeartbeat();
    unawaited(_onHeartbeatTimeout());
  }

  void _startSessionClosedAckTimer() {
    _sessionClosedAckTimer?.cancel();
    _sessionClosedAckTimer = Timer(const Duration(seconds: 5), () {
      if (_sessionClosedAcked) return;
      _log.warning('Session close was not acknowledged');
    });
  }
}
