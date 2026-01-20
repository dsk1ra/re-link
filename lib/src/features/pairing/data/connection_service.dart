import 'package:application/src/rust/api/connection.dart' as rust_connection;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Service for managing connection-based blind rendezvous pairing
class ConnectionService {
  final String signalingBaseUrl;
  final http.Client httpClient;

  ConnectionService({
    required this.signalingBaseUrl,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  /// Step 1: Initialize a connection locally (Client A)
  /// Generates a high-entropy secret and derives encryption keys
  /// Does not communicate with server
  Future<ConnectionInitResult> initializeConnectionLocally() async {
    final result = rust_connection.connectionInitLocal();
    return ConnectionInitResult(
      rendezvousId: result.rendezvousId,
      mailboxId: result.mailboxId,
      secret: result.secret,
      kSig: result.kSig,
      kMac: result.kMac,
      sas: result.sas,
    );
  }

  /// Generate a shareable connection link
  String generateConnectionLink(String rendezvousId, String secret) {
    return rust_connection.generateConnectionLink(
      baseUrl: signalingBaseUrl,
      rendezvousId: rendezvousId,
      secret: secret,
    );
  }

  /// Step 2: Send connection init to server (Client A)
  /// Server creates a mailbox and stores the rendezvous token
  Future<Map<String, dynamic>> sendConnectionInit({
    required String clientId,
    required String sessionToken,
    required String rendezvousId,
  }) async {
    final response = await httpClient.post(
      Uri.parse('$signalingBaseUrl/connection/init'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_id': clientId,
        'session_token': sessionToken,
        'rendezvous_id_b64': rendezvousId,
      }),
    );

    if (response.statusCode != 200) {
      print('Connection Init Failed: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to init connection: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Step 3: Join connection with token (Client B)
  /// Extracts token from the link and joins with the initiator's mailbox
  Future<Map<String, dynamic>> joinConnection({
    required String tokenB64,
  }) async {
    final response = await httpClient.post(
      Uri.parse('$signalingBaseUrl/connection/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token_b64': tokenB64,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to join connection: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Send an encrypted signal through the mailbox
  Future<void> sendSignal({
    required String mailboxId,
    required String ciphertextB64,
    int retries = 3,
  }) async {
    int attempt = 0;
    while (attempt < retries) {
      attempt++;
      try {
        final response = await httpClient.post(
          Uri.parse('$signalingBaseUrl/connection/send'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'mailbox_id': mailboxId,
            'ciphertext_b64': ciphertextB64,
          }),
        );

        if (response.statusCode == 202) return; // Success

        if (response.statusCode == 500 && attempt < retries) {
          print('Send signal 500 (Attempt $attempt), retrying...');
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }

        throw Exception('Failed to send signal: ${response.statusCode}');
      } catch (e) {
        if (attempt >= retries) rethrow;
        print('Send signal error (Attempt $attempt): $e, retrying...');
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }

  /// Fetch messages from mailbox
  Future<List<Map<String, dynamic>>> fetchMessages({
    required String mailboxId,
  }) async {
    final response = await httpClient.post(
      Uri.parse('$signalingBaseUrl/connection/recv'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'mailbox_id': mailboxId,
        // server expects same shape as MailboxSendRequest
        'ciphertext_b64': '',
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch messages: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final messagesList = data['messages'] as List<dynamic>? ?? [];

    return messagesList
        .map((msg) => msg as Map<String, dynamic>)
        .toList();
  }

  /// Subscribe to mailbox push events over WebSocket
  /// Emits each message as a decoded Map
  Stream<Map<String, dynamic>> subscribeMailbox({
    required String mailboxId,
  }) {
    String wsUrl;
    if (signalingBaseUrl.startsWith('https://')) {
      wsUrl = signalingBaseUrl.replaceFirst('https://', 'wss://');
    } else if (signalingBaseUrl.startsWith('http://')) {
      wsUrl = signalingBaseUrl.replaceFirst('http://', 'ws://');
    } else {
      wsUrl = signalingBaseUrl; // Fallback
    }
    
    final uri = Uri.parse('$wsUrl/ws/$mailboxId');
    print('Connecting to WebSocket: $uri');
    final channel = WebSocketChannel.connect(uri);

    // Map text frames into JSON maps
    return channel.stream.where((e) => e is String).map((e) {
      final text = e as String;
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    });
  }

  void dispose() {
    httpClient.close();
  }
}

/// Local result from connection initialization
class ConnectionInitResult {
  final String rendezvousId;  // Share via link
  final String mailboxId;     // Keep private
  final String secret;        // Shared secret (hex)
  final String kSig;          // Encryption key (hex)
  final String kMac;          // MAC key (hex)
  final String sas;           // Short auth string (hex)

  ConnectionInitResult({
    required this.rendezvousId,
    required this.mailboxId,
    required this.secret,
    required this.kSig,
    required this.kMac,
    required this.sas,
  });
}
