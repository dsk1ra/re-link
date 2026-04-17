import 'package:application/src/rust/api/connection.dart' as rust_connection;
import 'package:application/src/features/network/data/windows_tls_compat.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';
import 'dart:convert';

/// Service for managing connection-based blind rendezvous pairing
class ConnectionService {
  static final Logger _log = Logger('ConnectionService');
  static const Duration _initialReconnectDelay = Duration(milliseconds: 250);
  static const Duration _maxReconnectDelay = Duration(seconds: 2);
  final String signalingBaseUrl;
  final http.Client httpClient;

  ConnectionService({required this.signalingBaseUrl, http.Client? httpClient})
    : httpClient =
          httpClient ?? createPlatformHttpClientForBaseUrl(signalingBaseUrl);

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
    required String rendezvousId,
  }) async {
    final response = await httpClient.post(
      Uri.parse('$signalingBaseUrl/connection/init'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'rendezvous_id_b64': rendezvousId}),
    );

    if (response.statusCode != 200) {
      _log.warning('Connection init failed with status ${response.statusCode}');
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
      body: jsonEncode({'token_b64': tokenB64}),
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

        if (response.statusCode == 429 && attempt < retries) {
          await Future.delayed(
            Duration(milliseconds: 1000 * attempt),
          ); // Longer backoff
          continue;
        }

        if (response.statusCode == 500 && attempt < retries) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }

        throw Exception('Failed to send signal: ${response.statusCode}');
      } catch (_) {
        if (attempt >= retries) rethrow;
        _log.warning('Send signal failed; retrying');
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

    return messagesList.map((msg) => msg as Map<String, dynamic>).toList();
  }

  /// Subscribe to mailbox messages using WebSockets
  Stream<Map<String, dynamic>> subscribeMailbox({required String mailboxId}) {
    final wsBaseUrl = signalingBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final wsUrl = '$wsBaseUrl/ws/$mailboxId';

    final controller = StreamController<Map<String, dynamic>>.broadcast(
      sync: true,
    );
    WebSocketChannel? channel;
    bool isDisposed = false;
    bool isConnecting = false;
    int reconnectAttempt = 0;
    Timer? reconnectTimer;
    final deliveredMessages = <String>{};
    late Future<void> Function() connect;

    String messageKey(Map<String, dynamic> msg) {
      final sender = msg['from_mailbox_id'] as String? ?? '';
      final payload = msg['ciphertext_b64'] as String? ?? '';
      return '$sender:$payload';
    }

    void emitIfNew(Map<String, dynamic> msg) {
      final key = messageKey(msg);
      if (!deliveredMessages.add(key) || controller.isClosed) {
        return;
      }
      controller.add(msg);
    }

    Future<void> syncMailboxHistory() async {
      try {
        final messages = await fetchMessages(mailboxId: mailboxId);
        for (final msg in messages) {
          emitIfNew(msg);
        }
      } catch (_) {
        _log.warning('Mailbox sync failed');
      }
    }

    Duration nextReconnectDelay() {
      var delay = _initialReconnectDelay;
      for (var i = 0; i < reconnectAttempt; i++) {
        final doubled = delay * 2;
        delay = doubled > _maxReconnectDelay ? _maxReconnectDelay : doubled;
      }
      return delay;
    }

    void scheduleReconnect() {
      if (isDisposed || reconnectTimer != null) return;
      final delay = nextReconnectDelay();
      reconnectAttempt++;
      reconnectTimer = Timer(delay, () {
        reconnectTimer = null;
        unawaited(connect());
      });
    }

    connect = () async {
      if (isDisposed || isConnecting) return;
      isConnecting = true;

      try {
        final nextChannel = connectPlatformWebSocket(wsUrl);
        channel = nextChannel;

        nextChannel.stream.listen(
          (data) {
            if (isDisposed || channel != nextChannel) return;
            try {
              final msg = jsonDecode(data as String);
              emitIfNew(msg as Map<String, dynamic>);
            } catch (_) {
              _log.warning('WebSocket message decode failed');
            }
          },
          onError: (_) {
            if (channel != nextChannel) return;
            _log.warning('WebSocket connection error');
            scheduleReconnect();
          },
          onDone: () {
            if (channel != nextChannel) return;
            scheduleReconnect();
          },
        );

        reconnectAttempt = 0;
        unawaited(syncMailboxHistory());
      } catch (_) {
        _log.warning('WebSocket connection failed');
        scheduleReconnect();
      } finally {
        isConnecting = false;
      }
    };

    unawaited(connect());

    controller.onCancel = () {
      isDisposed = true;
      reconnectTimer?.cancel();
      channel?.sink.close();
      controller.close();
    };

    return controller.stream;
  }

  /// Close and delete mailbox data on the server
  Future<void> closeConnection({required String mailboxId}) async {
    final response = await httpClient.post(
      Uri.parse('$signalingBaseUrl/connection/close'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'mailbox_id': mailboxId}),
    );

    if (response.statusCode != 202) {
      throw Exception('Failed to close connection: ${response.statusCode}');
    }
  }

  void dispose() {
    httpClient.close();
  }
}

/// Local result from connection initialization
class ConnectionInitResult {
  final String rendezvousId; // Share via link
  final String mailboxId; // Keep private
  final String secret; // Shared secret (hex)
  final String kSig; // Encryption key (hex)
  final String kMac; // MAC key (hex)
  final String sas; // Short auth string (hex)

  ConnectionInitResult({
    required this.rendezvousId,
    required this.mailboxId,
    required this.secret,
    required this.kSig,
    required this.kMac,
    required this.sas,
  });
}
