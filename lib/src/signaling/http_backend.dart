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

  /// Returns the list of currently connected clients with their display names.
  Future<List<ClientInfo>> listClients() async {
    final uri = Uri.parse('$baseUrl/clients');
    final resp = await _client.get(uri, headers: {'Content-Type': 'application/json'});
    if (resp.statusCode != 200) {
      throw Exception('listClients failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (data['clients'] as List? ?? [])
        .map((e) => ClientInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    // Filter out self for convenience
    return list;
  }

  Future<void> dispose() async {
    _heartbeatTimer?.cancel();
    _client.close();
  }
}

class ClientInfo {
  final String clientId;
  final String displayName;
  ClientInfo({required this.clientId, required this.displayName});
  factory ClientInfo.fromJson(Map<String, dynamic> json) => ClientInfo(
        clientId: json['client_id'] as String,
        displayName: json['display_name'] as String,
      );
}

// ------- Simplified Global Chat API (client-side) -------
extension HttpSignalingBackendChat on HttpSignalingBackend {
  Future<void> chatSend(String text) async {
    if (!isRegistered) throw Exception('Not registered');
    final uri = Uri.parse('$baseUrl/chat/send');
    final resp = await _client.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'client_id': _clientId,
          'session_token': _sessionToken,
          'text': text,
        }));
    if (resp.statusCode != 202) {
      throw Exception('chatSend failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<List<ChatMessage>> chatList() async {
    if (!isRegistered) return [];
    final uri = Uri.parse('$baseUrl/chat/list');
    final resp = await _client.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'client_id': _clientId,
          'session_token': _sessionToken,
        }));
    if (resp.statusCode != 200) {
      throw Exception('chatList failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (data['messages'] as List? ?? [])
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }
}

class ChatMessage {
  final int id;
  final String fromClientId;
  final String fromDisplayName;
  final String text;
  final BigInt createdAtEpochMs;

  ChatMessage({
    required this.id,
    required this.fromClientId,
    required this.fromDisplayName,
    required this.text,
    required this.createdAtEpochMs,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: (json['id'] as num).toInt(),
        fromClientId: json['from_client_id'] as String,
        fromDisplayName: json['from_display_name'] as String,
        text: json['text'] as String,
        createdAtEpochMs: BigInt.parse(json['created_at_epoch_ms'].toString()),
      );
}
