import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Models
class SignalMessage {
  final String from;
  final String payload;
  final DateTime createdAt;
  SignalMessage({required this.from, required this.payload, required this.createdAt});
}

/// HTTP polling signaling client sufficient for demoing
/// producer/consumer style messaging between this client and itself (loopback).
class SignalingClient {
  final String baseUrl;
  final http.Client _http;

  String? _clientId;
  String? _sessionToken;
  int _heartbeatSecs = 30;
  Timer? _hbTimer;

  SignalingClient(this.baseUrl, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  String? get clientId => _clientId;
  String? get sessionToken => _sessionToken;
  bool get isReady => _clientId != null && _sessionToken != null;

  Future<void> register({String deviceLabel = 'flutter'}) async {
    final resp = await _http.post(Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_label': deviceLabel}));
    if (resp.statusCode != 200) {
      throw Exception('register failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    _clientId = data['client_id'] as String;
    _sessionToken = data['session_token'] as String;
    _heartbeatSecs = data['heartbeat_interval_secs'] as int? ?? 30;
    _scheduleHeartbeat();
  }

  void _scheduleHeartbeat() {
    _hbTimer?.cancel();
    if (!isReady) return;
    _hbTimer = Timer.periodic(Duration(seconds: _heartbeatSecs), (_) {
      heartbeat();
    });
  }

  Future<void> heartbeat() async {
    if (!isReady) return;
    final resp = await _http.post(Uri.parse('$baseUrl/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'client_id': _clientId, 'session_token': _sessionToken}));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _heartbeatSecs = data['next_heartbeat_secs'] as int? ?? _heartbeatSecs;
      _scheduleHeartbeat();
    }
  }

  Future<void> sendToSelf(String payload) async {
    if (!isReady) throw Exception('not registered');
    final body = {
      'session_token': _sessionToken,
      'envelope': {
        'from': _clientId,
        'to': _clientId,
        'payload': payload,
        'created_at_epoch_ms': 0,
      }
    };
    final resp = await _http.post(Uri.parse('$baseUrl/signal'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (resp.statusCode != 202) {
      throw Exception('send failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<List<SignalMessage>> pollMessages() async {
    if (!isReady) return [];
    final resp = await _http.post(Uri.parse('$baseUrl/signal/fetch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'client_id': _clientId, 'session_token': _sessionToken}));
    if (resp.statusCode != 200) {
      throw Exception('fetch failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (data['messages'] as List? ?? []);
    return list.map((raw) {
      final m = raw as Map<String, dynamic>;
      return SignalMessage(
        from: m['from'] as String,
        payload: m['payload'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(int.parse(m['created_at_epoch_ms'].toString())),
      );
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> dispose() async {
    _hbTimer?.cancel();
    _http.close();
  }
}
