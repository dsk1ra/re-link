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
    SessionAsyncCallback? onIceRestartRequested,
    SessionNowProvider? nowProvider,
  }) : _log = log,
       _sendPing = sendPing,
       _sendSessionClosed = sendSessionClosed,
       _onHeartbeatTimeout = onHeartbeatTimeout,
       _onIceRestartRequested = onIceRestartRequested,
       _nowProvider = nowProvider ?? DateTime.now;

  final Logger _log;
  final SessionPingSender _sendPing;
  final SessionClosedSender _sendSessionClosed;
  final SessionAsyncCallback _onHeartbeatTimeout;
  final SessionAsyncCallback? _onIceRestartRequested;
  final SessionNowProvider _nowProvider;

  static const _pingInterval = Duration(seconds: 5);
  static const _pongTimeout = Duration(seconds: 15);
  static const _iceRestartTimeout = Duration(seconds: 15);

  Timer? _heartbeatTimer;
  Timer? _iceRestartTimer;
  Timer? _sessionClosedAckTimer;
  DateTime? _lastPongAt;
  String? _sessionClosedId;
  bool _sessionClosedAcked = false;
  bool _iceRestartInProgress = false;

  void startHeartbeat() {
    stopHeartbeat();
    _lastPongAt = _nowProvider();
    _heartbeatTimer = Timer.periodic(_pingInterval, (_) {
      final last = _lastPongAt;
      if (last != null &&
          _nowProvider().difference(last) > _pongTimeout) {
        _handlePongTimeout();
        return;
      }

      unawaited(_sendPing(_nowProvider().millisecondsSinceEpoch.toString()));
    });
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _cancelIceRestart();
  }

  void dispose() {
    stopHeartbeat();
    _sessionClosedAckTimer?.cancel();
    _sessionClosedAckTimer = null;
  }

  void handlePong() {
    _lastPongAt = _nowProvider();
    if (_iceRestartInProgress) {
      _log.info('Pong received after ICE restart — connection recovered');
      _cancelIceRestart();
    }
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

  void _handlePongTimeout() {
    if (_iceRestartInProgress) return;

    if (_onIceRestartRequested != null) {
      _log.warning('Heartbeat pong timeout — attempting ICE restart');
      _iceRestartInProgress = true;
      unawaited(_onIceRestartRequested());
      _iceRestartTimer = Timer(_iceRestartTimeout, () {
        if (!_iceRestartInProgress) return;
        _log.warning('ICE restart failed — closing session');
        _iceRestartInProgress = false;
        _finalizeTimeout();
      });
    } else {
      _finalizeTimeout();
    }
  }

  void _finalizeTimeout() {
    _log.warning('Session heartbeat timed out');
    stopHeartbeat();
    unawaited(_onHeartbeatTimeout());
  }

  void _cancelIceRestart() {
    _iceRestartInProgress = false;
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
  }

  void _startSessionClosedAckTimer() {
    _sessionClosedAckTimer?.cancel();
    _sessionClosedAckTimer = Timer(const Duration(seconds: 5), () {
      if (_sessionClosedAcked) return;
      _log.warning('Session close was not acknowledged');
    });
  }
}
