import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../pairing/domain/models.dart';
import '../../../pairing/domain/signaling_backend.dart';

/// HTTP client for the signaling server implementing the domain interface.
class HttpSignalingBackend implements SignalingBackend {
  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  String? _clientId;
  String? _sessionToken;
  int _heartbeatIntervalSecs = 30;
  Timer? _heartbeatTimer;
  String? _displayName;

  HttpSignalingBackend(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  @override
  bool get isRegistered => _clientId != null && _sessionToken != null;
  @override
  String? get clientId => _clientId;
  @override
  String? get sessionToken => _sessionToken;
  @override
  String? get displayName => _displayName;

  @override
  Future<RegisterResponse> register({required String deviceLabel}) async {
    final uri = Uri.parse('$baseUrl/register');
    final resp = await _client.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_label': deviceLabel}));
    if (resp.statusCode != 200) {
      throw Exception('Register failed: ${resp.statusCode} ${resp.body}');
    }
    final data = RegisterResponse.fromJson(jsonDecode(resp.body));
    _clientId = data.clientId;
    _sessionToken = data.sessionToken;
    _heartbeatIntervalSecs = data.heartbeatIntervalSecs;
    _displayName = data.displayName;
    _scheduleNextHeartbeat(_heartbeatIntervalSecs);
    return data;
  }

  void _scheduleNextHeartbeat([int? seconds]) {
    _heartbeatTimer?.cancel();
    if (!isRegistered) return;
    final delay = Duration(seconds: (seconds ?? _heartbeatIntervalSecs).clamp(1, 3600));
    _heartbeatTimer = Timer(delay, () async {
      try {
        final hb = await heartbeat();
        // next interval already updated in heartbeat()
        if (hb != null) {
          _scheduleNextHeartbeat(_heartbeatIntervalSecs);
        }
      } catch (_) {
        // On transient error, try again after the current interval
        _scheduleNextHeartbeat(_heartbeatIntervalSecs);
      }
    });
  }

  @override
  Future<HeartbeatResponse?> heartbeat() async {
    if (!isRegistered) return null;
    final uri = Uri.parse('$baseUrl/heartbeat');
    final resp = await _client.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'client_id': _clientId, 'session_token': _sessionToken}));
    if (resp.statusCode == 200) {
      final hb = HeartbeatResponse.fromJson(jsonDecode(resp.body));
      _heartbeatIntervalSecs = hb.nextHeartbeatSecs;
      return hb;
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    _heartbeatTimer?.cancel();
    if (_ownsClient) {
      _client.close();
    }
  }
}
