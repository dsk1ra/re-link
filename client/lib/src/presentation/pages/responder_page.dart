import 'dart:async';
import 'dart:convert';

import 'package:application/src/features/file_transfer/file_transfer_widget.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:application/src/features/pairing/data/connection_service.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:application/src/rust/api/connection.dart' as rust_connection;
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Responder screen - joins using connection link
class ResponderPage extends StatefulWidget {
  final String signalingBaseUrl;
  final SignalingBackend backend;
  final String? initialToken;

  const ResponderPage({
    super.key,
    required this.signalingBaseUrl,
    required this.backend,
    this.initialToken,
  });

  @override
  State<ResponderPage> createState() => _ResponderPageState();
}

class _ResponderPageState extends State<ResponderPage> {
  static final Logger _log = Logger('ResponderPage');
  late ConnectionService _connectionService;
  WebRTCManager? _webrtcManager;

  RTCPeerConnectionState? _webrtcState;
  String? _receivedMessage;

  final TextEditingController _tokenController = TextEditingController();
  String? _responderMailboxId;
  String? _kSig; // Session encryption key
  bool _joiningConnection = false;
  String? _joinError;
  bool _joined = false;
  bool _isPeerDisconnected = false;

  final List<RTCIceCandidate> _iceCandidateQueue = [];
  bool _isSendingIce = false;

  @override
  void initState() {
    super.initState();
    _connectionService = ConnectionService(
      signalingBaseUrl: widget.signalingBaseUrl,
    );
    // ...
  }

  // ...

  Future<void> _startWebRTCHandshake() async {
    try {
      _webrtcManager = WebRTCManager();
      await _webrtcManager!.initialize();

      _webrtcManager!.onStateChange.listen((state) {
        _log.info('Responder: State changed to $state');
        setState(() => _webrtcState = state);
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _showSnackBar('WebRTC connected!');
        }
      });

      _webrtcManager!.onMessage.listen((message) {
        setState(() => _receivedMessage = message);
        _showSnackBar('Received: $message');
      });

      _webrtcManager!.onIceCandidate.listen(
        (candidate) => _queueIceCandidate(candidate),
      );

      // 1. Process any messages already waiting in the mailbox (e.g. the Offer)
      await _fetchAndProcessExistingMessages();

      // 2. Listen for new messages (e.g. ICE candidates)
      _startListeningForSignals();
    } catch (e) {
      _showSnackBar('WebRTC error: $e');
    }
  }

  void _queueIceCandidate(RTCIceCandidate candidate) {
    _iceCandidateQueue.add(candidate);
    if (!_isSendingIce) {
      _processIceQueue();
    }
  }

  Future<void> _processIceQueue() async {
    if (_isSendingIce || _iceCandidateQueue.isEmpty) return;

    _isSendingIce = true;
    try {
      while (_iceCandidateQueue.isNotEmpty) {
        final candidate = _iceCandidateQueue.removeAt(0);
        await _sendIceCandidate(candidate);
        // Small delay to be nice to the server
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      _log.warning('Error sending queued ICE candidate: $e');
    } finally {
      _isSendingIce = false;
      // Double check in case new ones came in
      if (_iceCandidateQueue.isNotEmpty) _processIceQueue();
    }
  }

  StreamSubscription? _mailboxSubscription;
  final List<Map<String, dynamic>> _signalQueue = [];
  bool _isProcessingSignals = false;

  @override
  void dispose() {
    _connectionService.dispose();
    _tokenController.dispose();
    _mailboxSubscription?.cancel();
    _webrtcManager?.dispose();
    super.dispose();
  }

  // ...
  Future<void> _joinWithToken() async {
    final input = _tokenController.text.trim();
    if (input.isEmpty) {
      _showSnackBar('Enter connection link');
      return;
    }

    String token = input;
    String? secret;

    try {
      final uri = Uri.parse(input);
      if (uri.hasQuery && uri.queryParameters.containsKey('token')) {
        token = uri.queryParameters['token']!;
      }
      // Extract secret from fragment (e.g. #secret_hex)
      if (uri.hasFragment && uri.fragment.isNotEmpty) {
        secret = uri.fragment;
      }
    } catch (_) {}

    // If we have no secret, we cannot derive keys for E2EE
    if (secret == null) {
      setState(() {
        _joinError = 'Invalid link: Missing security key (fragment)';
      });
      return;
    }

    setState(() {
      _joiningConnection = true;
      _joinError = null;
    });

    try {
      // Derive keys locally
      final keys = rust_connection.connectionDeriveKeys(secretHex: secret);
      _kSig = keys.kSig;

      final joinResult = await _connectionService.joinConnection(
        tokenB64: token,
      );
      final mailboxId = joinResult['mailbox_id'] as String;

      final hello = jsonEncode({
        'type': 'connect_request',
        'note': 'Peer wants to connect',
      });

      final helloB64 = rust_connection.connectionEncrypt(
        keyHex: _kSig!,
        plaintext: utf8.encode(hello),
      );

      await _connectionService.sendSignal(
        mailboxId: mailboxId,
        ciphertextB64: helloB64,
      );

      setState(() {
        _responderMailboxId = mailboxId;
        _joiningConnection = false;
        _joined = true;
      });

      await _startWebRTCHandshake();
    } catch (e) {
      setState(() {
        _joiningConnection = false;
        _joinError = e.toString();
      });
    }
  }

  Future<void> _fetchAndProcessExistingMessages() async {
    try {
      final messages = await _connectionService.fetchMessages(
        mailboxId: _responderMailboxId!,
      );
      for (final msg in messages) {
        await _handleIncomingSignal(msg);
      }
    } catch (e) {
      _log.warning('Failed to fetch existing messages: $e');
    }
  }

  void _startListeningForSignals() {
    _mailboxSubscription?.cancel();
    _mailboxSubscription = _connectionService
        .subscribeMailbox(mailboxId: _responderMailboxId!)
        .listen((msg) {
          _queueIncomingSignal(msg);
        });
  }

  void _queueIncomingSignal(Map<String, dynamic> msg) {
    _signalQueue.add(msg);
    if (!_isProcessingSignals) {
      _processSignalQueue();
    }
  }

  Future<void> _processSignalQueue() async {
    if (_isProcessingSignals || _signalQueue.isEmpty) return;

    _isProcessingSignals = true;
    try {
      while (_signalQueue.isNotEmpty) {
        final msg = _signalQueue.removeAt(0);
        await _handleIncomingSignal(msg);
      }
    } catch (e) {
      _log.warning('Error processing signal queue: $e');
    } finally {
      _isProcessingSignals = false;
      if (_signalQueue.isNotEmpty) _processSignalQueue();
    }
  }

  Future<void> _handleIncomingSignal(Map<String, dynamic> msg) async {
    final payloadB64 = msg['ciphertext_b64'] as String?;
    if (payloadB64 == null || payloadB64.isEmpty) return;

    if (_kSig == null) return;

    try {
      final decryptedBytes = rust_connection.connectionDecrypt(
        keyHex: _kSig!,
        ciphertextB64: payloadB64,
      );
      final decoded = utf8.decode(decryptedBytes);
      _log.info('Responder: Received Signal: $decoded');
      final signalingMsg = SignalingMessage.fromJsonString(decoded);

      if (signalingMsg.type == 'offer') {
        _log.info('Responder: Processing Offer...');
        final offer = RTCSessionDescription(
          signalingMsg.data['sdp'] as String,
          signalingMsg.data['type'] as String,
        );
        final answer = await _webrtcManager!.createAnswer(offer);
        _log.info('Responder: Created Answer');

        final answerMsg = SignalingMessage(
          type: 'answer',
          data: {'sdp': answer.sdp, 'type': answer.type},
        );
        final answerB64 = rust_connection.connectionEncrypt(
          keyHex: _kSig!,
          plaintext: utf8.encode(answerMsg.toJsonString()),
        );
        await _connectionService.sendSignal(
          mailboxId: _responderMailboxId!,
          ciphertextB64: answerB64,
        );
        _log.info('Responder: Sent Answer');
      } else if (signalingMsg.type == 'ice') {
        _log.info('Responder: Processing ICE Candidate...');
        final candidate = RTCIceCandidate(
          signalingMsg.data['candidate'] as String,
          signalingMsg.data['sdpMid'] as String,
          signalingMsg.data['sdpMLineIndex'] as int,
        );
        await _webrtcManager!.addIceCandidate(candidate);
      } else if (signalingMsg.type == 'disconnect') {
        _log.info('Responder: Peer disconnected');
        _showSnackBar('Peer has disconnected.');
        await _webrtcManager?.dispose();
        setState(() {
          _webrtcManager = null;
          _webrtcState = null;
          _isPeerDisconnected = true;
        });
      }
    } catch (e) {
      _log.warning('Responder: Error handling signal: $e');
    }
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    if (_kSig == null) return;

    final iceMsg = SignalingMessage(
      type: 'ice',
      data: {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    );
    final iceB64 = rust_connection.connectionEncrypt(
      keyHex: _kSig!,
      plaintext: utf8.encode(iceMsg.toJsonString()),
    );
    await _connectionService.sendSignal(
      mailboxId: _responderMailboxId!,
      ciphertextB64: iceB64,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _webrtcStateText() {
    if (_isPeerDisconnected) return 'Disconnected';
    switch (_webrtcState) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return 'Connecting';
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return 'Connected';
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return 'Failed';
      default:
        return 'Waiting';
    }
  }

  Future<void> _sendDisconnectSignal() async {
    if (_kSig == null || _responderMailboxId == null) return;
    try {
      final msg = SignalingMessage(type: 'disconnect', data: {});
      final encryptedB64 = rust_connection.connectionEncrypt(
        keyHex: _kSig!,
        plaintext: utf8.encode(msg.toJsonString()),
      );
      await _connectionService.sendSignal(
        mailboxId: _responderMailboxId!,
        ciphertextB64: encryptedB64,
      );
    } catch (e) {
      _log.warning('Error sending disconnect signal: $e');
    }
  }

  Future<bool> _showExitConfirmation() async {
    if (_webrtcState !=
            RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
        _webrtcState !=
            RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Connection?'),
        content: const Text(
          'You are currently in an active secure session. Disconnecting will end the peer-to-end connection for both parties.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Connected'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFcc3f0c),
              foregroundColor: Colors.white,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _sendDisconnectSignal();
    }
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showExitConfirmation();
        if (!mounted) return;
        if (shouldPop) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFd8cbc7),
        appBar: AppBar(
          title: const Text(
            'Join Connection',
            style: TextStyle(color: Color(0xFFffffff)),
          ),
          backgroundColor: const Color(0xFF19231a),
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFFffffff)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_joined) ...[
                const Text(
                  'Enter connection link',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _tokenController,
                  style: const TextStyle(color: Color(0xFF19231a)),
                  decoration: const InputDecoration(
                    labelText: 'Paste link or token',
                    labelStyle: TextStyle(color: Color(0xFF19231a)),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF19231a)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Color(0xFFcc3f0c),
                        width: 2,
                      ),
                    ),
                    prefixIcon: Icon(Icons.link, color: Color(0xFF19231a)),
                    filled: true,
                    fillColor: Color(0xFFffffff),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _joiningConnection ? null : _joinWithToken,
                  icon: _joiningConnection
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(
                    _joiningConnection ? 'Joining...' : 'Join Connection',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFcc3f0c),
                    foregroundColor: const Color(0xFFffffff),
                    disabledBackgroundColor: const Color(
                      0xFF19231a,
                    ).withAlpha(77),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                if (_joinError != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: const Color(0xFFffffff),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Error',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFcc3f0c),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _joinError!,
                            style: const TextStyle(color: Color(0xFF19231a)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ] else ...[
                Card(
                  color: const Color(0xFFffffff),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          _isPeerDisconnected
                              ? Icons.cancel
                              : (_webrtcState ==
                                        RTCPeerConnectionState
                                            .RTCPeerConnectionStateConnected
                                    ? Icons.check_circle
                                    : Icons.sync),
                          size: 64,
                          color: _isPeerDisconnected
                              ? Colors.red
                              : (_webrtcState ==
                                        RTCPeerConnectionState
                                            .RTCPeerConnectionStateConnected
                                    ? const Color(0xFFcc3f0c)
                                    : const Color(0xFF19231a)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isPeerDisconnected
                              ? 'Connection Ended'
                              : (_webrtcState ==
                                        RTCPeerConnectionState
                                            .RTCPeerConnectionStateConnected
                                    ? 'Connected!'
                                    : 'Establishing Connection...'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'WebRTC: ${_webrtcStateText()}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        if (_isPeerDisconnected) ...[
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Return to Home'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_webrtcState ==
                    RTCPeerConnectionState.RTCPeerConnectionStateConnected) ...[
                  const SizedBox(height: 16),
                  if (_webrtcManager != null)
                    FileTransferWidget(webrtcManager: _webrtcManager!),
                  if (_receivedMessage != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: const Color(0xFFffffff),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Received Message',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF19231a),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _receivedMessage!,
                              style: const TextStyle(color: Color(0xFF19231a)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
