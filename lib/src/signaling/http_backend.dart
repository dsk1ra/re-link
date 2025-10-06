import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Data models matching the Rust signaling server JSON API.
class RegisterResponse {
  final String clientId; // UUID
  final String sessionToken;
  final int heartbeatIntervalSecs;

  RegisterResponse({
    required this.clientId,
    required this.sessionToken,
    required this.heartbeatIntervalSecs,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) => RegisterResponse(
        clientId: json['client_id'] as String,
        sessionToken: json['session_token'] as String,
        heartbeatIntervalSecs: json['heartbeat_interval_secs'] as int,
      );
}

class HeartbeatResponse {
  final int nextHeartbeatSecs;
  HeartbeatResponse(this.nextHeartbeatSecs);
  factory HeartbeatResponse.fromJson(Map<String, dynamic> json) =>
      HeartbeatResponse(json['next_heartbeat_secs'] as int);
}

class SignalEnvelope {
  final String from;
  final String to;
  final String payload;
  final BigInt createdAtEpochMs;

  SignalEnvelope({
    required this.from,
    required this.to,
    required this.payload,
    required this.createdAtEpochMs,
  });

  factory SignalEnvelope.fromJson(Map<String, dynamic> json) => SignalEnvelope(
        from: json['from'] as String,
        to: json['to'] as String,
        payload: json['payload'] as String,
        createdAtEpochMs: BigInt.parse(json['created_at_epoch_ms'].toString()),
      );
}

class SignalFetchResponse {
  final List<SignalEnvelope> messages;
  SignalFetchResponse(this.messages);
  factory SignalFetchResponse.fromJson(Map<String, dynamic> json) =>
      SignalFetchResponse(((json['messages'] as List?) ?? [])
          .map((e) => SignalEnvelope.fromJson(e as Map<String, dynamic>))
          .toList());
}

/// HTTP client for the signaling server
class HttpSignalingBackend {
  final String baseUrl;
  final http.Client _client;

  String? _clientId;
  String? _sessionToken;
  int _heartbeatIntervalSecs = 30;
  Timer? _heartbeatTimer;

  HttpSignalingBackend(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();

  bool get isRegistered => _clientId != null && _sessionToken != null;
  String? get clientId => _clientId;

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
    _scheduleHeartbeat();
    return data;
  }

  void _scheduleHeartbeat() {
    _heartbeatTimer?.cancel();
    if (!isRegistered) return;
    _heartbeatTimer = Timer.periodic(Duration(seconds: _heartbeatIntervalSecs), (_) {
      heartbeat();
    });
  }

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

  Future<void> sendSignal({
    required String to,
    required String payload,
  }) async {
    if (!isRegistered) throw Exception('Not registered');
    final uri = Uri.parse('$baseUrl/signal');
    final body = {
      'session_token': _sessionToken,
      'envelope': {
        'from': _clientId,
        'to': to,
        'payload': payload,
        'created_at_epoch_ms': 0, // server overwrites
      }
    };
    final resp = await _client.post(uri,
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (resp.statusCode != 202) {
      throw Exception('sendSignal failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<List<SignalEnvelope>> fetchSignals() async {
    if (!isRegistered) return [];
    final uri = Uri.parse('$baseUrl/signal/fetch');
    final resp = await _client.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'client_id': _clientId, 'session_token': _sessionToken}));
    if (resp.statusCode != 200) {
      throw Exception('fetchSignals failed: ${resp.statusCode} ${resp.body}');
    }
    final data = SignalFetchResponse.fromJson(jsonDecode(resp.body));
    return data.messages;
  }

  Future<void> dispose() async {
    _heartbeatTimer?.cancel();
    _client.close();
  }
}
