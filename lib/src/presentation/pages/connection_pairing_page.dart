import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:application/src/features/pairing/data/connection_service.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';

/// Uses blind rendezvous with single-use tokens
class ConnectionPairingPage extends StatefulWidget {
  final String signalingBaseUrl;
  final SignalingBackend backend;

  const ConnectionPairingPage({
    super.key,
    this.signalingBaseUrl = 'http://127.0.0.1:8080',
    required this.backend,
  });

  @override
  State<ConnectionPairingPage> createState() => _ConnectionPairingPageState();
}

class _ConnectionPairingPageState extends State<ConnectionPairingPage> {
  late ConnectionService _connectionService;
  
  // Connection state
  bool _connecting = false;
  String? _connectError;
  
  // State for initiator (client A)
  ConnectionInitResult? _initiatorResult;
  String? _connectionLink;
  String? _initiatorServerMailboxId;
  bool _generatingLink = false;
  bool _pollingPeer = false;
  Timer? _pollTimer;
  String? _incomingRequestFrom;
  String? _connectedPeerMailboxId;
  bool _peerAccepted = false;
  
  // State for responder (client B)
  final TextEditingController _tokenController = TextEditingController();
  String? _responderMailboxId;
  bool _joiningConnection = false;
  String? _joinError;

  @override
  void initState() {
    super.initState();
    _connectionService = ConnectionService(
      signalingBaseUrl: widget.signalingBaseUrl,
    );
    // Auto-connect to signaling server
    scheduleMicrotask(() => _connectToServer());
  }

  @override
  void dispose() {
    _connectionService.dispose();
    _tokenController.dispose();
    _pollTimer?.cancel();
    widget.backend.dispose();
    super.dispose();
  }

  Future<void> _connectToServer() async {
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    
    try {
      await widget.backend.register(deviceLabel: 'Flutter P2P Client');
      setState(() {
        _connecting = false;
      });
    } catch (e) {
      setState(() {
        _connecting = false;
        _connectError = e.toString();
      });
    }
  }

  // --- INITIATOR (Client A) FLOW ---

  Future<void> _createInitiatorLink() async {
    if (!widget.backend.isRegistered) {
      _showSnackBar('Not connected to server');
      return;
    }

    setState(() => _generatingLink = true);
    try {
      // Step 1: Generate local secret and keys
      final initResult = await _connectionService.initializeConnectionLocally();
      
      // Step 2: Generate shareable link
      final link = _connectionService.generateConnectionLink(initResult.rendezvousId);
      
      // Step 3: Register with server (may return a different mailbox_id)
      final initResp = await _connectionService.sendConnectionInit(
        clientId: widget.backend.clientId ?? '',
        sessionToken: widget.backend.sessionToken ?? '',
        rendezvousId: initResult.rendezvousId,
      );
      final serverMailboxId = initResp['mailbox_id'] as String?;

      // Start polling for incoming join requests using the server mailbox id
      if (serverMailboxId != null) {
        _initiatorServerMailboxId = serverMailboxId;
        _startPollingForPeer(serverMailboxId);
      }

      setState(() {
        _initiatorResult = initResult;
        _connectionLink = link;
        _generatingLink = false;
      });
      
      if (serverMailboxId == null) {
        _showSnackBar('Warning: server did not return mailbox id; polling may fail');
      }

      _showSnackBar('Link created! Share it with peer.');
    } catch (e) {
      setState(() => _generatingLink = false);
      _showSnackBar('Error creating link: $e');
    }
  }

  Future<void> _copyLinkToClipboard() async {
    if (_connectionLink == null) return;
    await Clipboard.setData(ClipboardData(text: _connectionLink!));
    _showSnackBar('Link copied to clipboard');
  }

  Future<void> _shareLinkWithPeer() async {
    if (_connectionLink == null) return;
    await Share.share(
      'Join me: $_connectionLink\n\nSAS: ${_initiatorResult?.sas}',
      subject: 'P2P Connection Link',
    );
  }

  // --- RESPONDER (Client B) FLOW ---

  Future<void> _joinWithToken() async {
    final input = _tokenController.text.trim();
    if (input.isEmpty) {
      _showSnackBar('Enter connection token');
      return;
    }

    // Extract token from full URL or use as-is
    String token = input;
    try {
      final uri = Uri.parse(input);
      if (uri.hasQuery && uri.queryParameters.containsKey('token')) {
        token = uri.queryParameters['token']!;
      }
    } catch (_) {
      // Not a valid URL, treat as raw token
    }

    setState(() => _joiningConnection = true);
    try {
      final joinResult = await _connectionService.joinConnection(tokenB64: token);
      final mailboxId = joinResult['mailbox_id'] as String;

      // Immediately signal the initiator that we want to connect
      final hello = jsonEncode({
        'type': 'connect_request',
        'note': 'Peer wants to connect',
      });
      final helloB64 = base64Url.encode(utf8.encode(hello));
      await _connectionService.sendSignal(
        mailboxId: mailboxId,
        ciphertextB64: helloB64,
      );
      
      setState(() {
        _responderMailboxId = mailboxId;
        _joiningConnection = false;
        _joinError = null;
      });

      _showSnackBar('Successfully joined! Mailbox: $mailboxId');
    } catch (e) {
      setState(() {
        _joiningConnection = false;
        _joinError = e.toString();
      });
      _showSnackBar('Error joining: $e');
    }
  }

  void _startPollingForPeer(String mailboxId) {
    _pollTimer?.cancel();
    _pollingPeer = true;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final messages = await _connectionService.fetchMessages(mailboxId: mailboxId);
        if (messages.isEmpty) return;

        final msg = messages.last;
        final from = msg['from_mailbox_id'] as String?;

        _pollTimer?.cancel();
        setState(() {
          _pollingPeer = false;
          _incomingRequestFrom = from;
        });

        _showIncomingDialog();
      } catch (_) {
        // Ignore transient errors
      }
    });
  }

  void _showIncomingDialog() {
    if (_incomingRequestFrom == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Incoming Connection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A peer wants to connect'),
              const SizedBox(height: 8),
              Text(
                'From: $_incomingRequestFrom',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _incomingRequestFrom = null;
                });
              },
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _connectedPeerMailboxId = _incomingRequestFrom;
                  _peerAccepted = true;
                  _incomingRequestFrom = null;
                });
                _showSnackBar('Connection accepted');
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _manualCheckForPeer() async {
    if (_initiatorResult == null) return;
    final mailboxId = _initiatorServerMailboxId ?? _initiatorResult!.mailboxId;
    await _connectionService.fetchMessages(mailboxId: mailboxId).then((messages) {
      if (messages.isEmpty) return;
      final msg = messages.last;
      final from = msg['from_mailbox_id'] as String?;

      setState(() {
        _incomingRequestFrom = from;
        _pollingPeer = false;
      });

      _showIncomingDialog();
    }).catchError((_) {
      // ignore errors
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.backend.isRegistered;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect'),
      ),
      body: Column(
        children: [
          // Connection status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: connected 
                ? Colors.green.shade50 
                : (_connecting ? Colors.orange.shade50 : Colors.red.shade50),
            child: Row(
              children: [
                if (_connecting) ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  const Text('Connecting...'),
                ] else if (connected) ...[
                  const Icon(Icons.cloud_done, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.backend.displayName ?? 'Connected',
                    ),
                  ),
                ] else ...[
                  const Icon(Icons.cloud_off, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connectError ?? 'Not connected',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _connectToServer,
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
          
          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // INITIATOR SECTION
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Create Link',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: (!connected || _generatingLink || _peerAccepted)
                                ? null
                                : _createInitiatorLink,
                            icon: _generatingLink
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.add_link),
                            label: Text(
                              _peerAccepted
                                  ? 'Connected'
                                  : (_generatingLink ? 'Creating...' : 'Create Link'),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                    if (_connectionLink != null && !_peerAccepted) ...[
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Scan QR Code',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: QrImageView(
                                data: _connectionLink!,
                                version: QrVersions.auto,
                                size: 200,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Or share link',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _connectionLink!,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _copyLinkToClipboard,
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copy'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _shareLinkWithPeer,
                                  icon: const Icon(Icons.share),
                                  label: const Text('Share'),
                                ),
                              ],
                            ),
                            if (_initiatorResult != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Verify code',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      _initiatorResult!.sas.substring(0, 16),
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (_peerAccepted && _connectedPeerMailboxId != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Connected',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Peer: $_connectedPeerMailboxId',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_pollingPeer) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          const Text('Waiting for peer...'),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _manualCheckForPeer(),
                            child: const Text('Refresh'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // RESPONDER SECTION
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Join',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _tokenController,
                      decoration: InputDecoration(
                        labelText: 'Paste link or token',
                        border: const OutlineInputBorder(),
                        suffixIcon: _tokenController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _tokenController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: (!connected || _joiningConnection || _tokenController.text.isEmpty)
                          ? null
                          : _joinWithToken,
                      icon: _joiningConnection
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(_joiningConnection ? 'Joining...' : 'Join'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                    if (_joinError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Error: $_joinError',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                    if (_responderMailboxId != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Connected',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ID: $_responderMailboxId',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],  // End of Column children (2 cards)
        ),    // End of Column
      ),      // End of SingleChildScrollView
    ),        // End of Expanded
    ],          // End of Column children (banner + expanded)
      ),        // End of Column (body)
    );          // End of Scaffold
  }             // End of build method
}               // End of class
