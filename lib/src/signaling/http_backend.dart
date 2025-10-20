import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Data models matching the Rust signaling server JSON API.
class RegisterResponse {
  final String clientId; // UUID
  final String sessionToken;
  final int heartbeatIntervalSecs;
  final String displayName;

  RegisterResponse({
    required this.clientId,
    required this.sessionToken,
    required this.heartbeatIntervalSecs,
    required this.displayName,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) => RegisterResponse(
        clientId: json['client_id'] as String,
        sessionToken: json['session_token'] as String,
        heartbeatIntervalSecs: json['heartbeat_interval_secs'] as int,
        displayName: json['display_name'] as String? ?? 'Client',
      );
}

class HeartbeatResponse {
  final int nextHeartbeatSecs;
  HeartbeatResponse(this.nextHeartbeatSecs);
  factory HeartbeatResponse.fromJson(Map<String, dynamic> json) =>
      HeartbeatResponse(json['next_heartbeat_secs'] as int);
}

/// HTTP client for the signaling server
class HttpSignalingBackend {
  final String baseUrl;
  final http.Client _client;

  String? _clientId;
  String? _sessionToken;
  int _heartbeatIntervalSecs = 30;
  Timer? _heartbeatTimer;
  String? _displayName;

  HttpSignalingBackend(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();

  bool get isRegistered => _clientId != null && _sessionToken != null;
  String? get clientId => _clientId;
  String? get sessionToken => _sessionToken;
  String? get displayName => _displayName;

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

  Future<void> dispose() async {
    _heartbeatTimer?.cancel();
    _client.close();
  }

}

// ------- Ephemeral Room Handshake API -------

class CreateRoomResponse {
  final String roomId; // 32-char hex
  final String password; // 32-char base64
  final String initiatorToken; // 64-char hex
  final BigInt? expiresAtEpochMs; // optional, for countdown
  final int? ttlSeconds; // optional

  CreateRoomResponse({
    required this.roomId,
    required this.password,
    required this.initiatorToken,
    this.expiresAtEpochMs,
    this.ttlSeconds,
  });

  factory CreateRoomResponse.fromJson(Map<String, dynamic> json) => CreateRoomResponse(
        roomId: json['room_id'] as String,
        password: json['password'] as String,
        initiatorToken: json['initiator_token'] as String,
        expiresAtEpochMs: json['expires_at_epoch_ms'] == null
            ? null
            : BigInt.parse(json['expires_at_epoch_ms'].toString()),
        ttlSeconds: (json['ttl_seconds'] as num?)?.toInt(),
      );
}

class JoinRoomResponse {
  final String initiatorToken; // 64-char hex
  final String receiverToken; // 64-char hex

  JoinRoomResponse({required this.initiatorToken, required this.receiverToken});

  factory JoinRoomResponse.fromJson(Map<String, dynamic> json) => JoinRoomResponse(
        initiatorToken: json['initiator_token'] as String,
        receiverToken: json['receiver_token'] as String,
      );
}

extension HttpSignalingBackendRoom on HttpSignalingBackend {
  /// Creates an ephemeral room on the server with a 30s TTL.
  /// Returns the roomId, plain password, and initiator token.
  Future<CreateRoomResponse> roomCreate() async {
    if (!isRegistered) throw Exception('Not registered');
    final uri = Uri.parse('$baseUrl/room/create');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_id': _clientId,
        'session_token': _sessionToken,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('roomCreate failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return CreateRoomResponse.fromJson(data);
  }

  /// Joins a room with the provided credentials. On success, the server will
  /// delete the room and return both initiator and receiver tokens.
  Future<JoinRoomResponse> roomJoin({required String roomId, required String password}) async {
    if (!isRegistered) throw Exception('Not registered');
    final uri = Uri.parse('$baseUrl/room/join');
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_id': _clientId,
        'session_token': _sessionToken,
        'room_id': roomId,
        'password': password,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('roomJoin failed: ${resp.statusCode} ${resp.body}');
    }
    return JoinRoomResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }
}
