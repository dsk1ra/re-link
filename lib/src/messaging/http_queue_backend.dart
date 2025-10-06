import 'dart:convert';
import 'package:http/http.dart' as http;

class HttpQueueBackend {
  final String baseUrl;
  final http.Client _http;
  final String clientId;
  final String sessionToken;

  HttpQueueBackend({required this.baseUrl, required this.clientId, required this.sessionToken, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  Future<void> produce(String payload) async {
    final resp = await _http.post(Uri.parse('$baseUrl/queue/produce'),
        headers: _headers,
        body: jsonEncode({
          'client_id': clientId,
          'session_token': sessionToken,
          'payload': payload,
        }));
    if (resp.statusCode != 202) {
      throw Exception('queue produce failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<String?> consume() async {
    final resp = await _http.post(Uri.parse('$baseUrl/queue/consume'),
        headers: _headers,
        body: jsonEncode({
          'client_id': clientId,
          'session_token': sessionToken,
        }));
    if (resp.statusCode != 200) {
      throw Exception('queue consume failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final item = data['item'];
    if (item == null) return null;
    return (item as Map<String, dynamic>)['payload'] as String;
  }

  Future<List<String>> list() async {
    final resp = await _http.post(Uri.parse('$baseUrl/queue/list'),
        headers: _headers,
        body: jsonEncode({
          'client_id': clientId,
          'session_token': sessionToken,
        }));
    if (resp.statusCode != 200) {
      throw Exception('queue list failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (data['items'] as List? ?? []);
    return items.map((e) => (e as Map<String, dynamic>)['payload'] as String).toList();
  }

  Future<void> dispose() async => _http.close();
}
