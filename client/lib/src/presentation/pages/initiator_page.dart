import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:application/src/features/pairing/data/connection_service.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:application/src/rust/api/connection.dart' as rust_connection;
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Initiator screen - creates and shares connection link
class InitiatorPage extends StatefulWidget {
  final String signalingBaseUrl;
  final SignalingBackend backend;

  const InitiatorPage({
    super.key,
    required this.signalingBaseUrl,
    required this.backend,
  });

  @override
  State<InitiatorPage> createState() => _InitiatorPageState();
}

class _InitiatorPageState extends State<InitiatorPage> {
  late ConnectionService _connectionService;
  WebRTCManager? _webrtcManager;

  RTCPeerConnectionState? _webrtcState;
  String? _receivedMessage;

  ConnectionInitResult? _initiatorResult;
  String? _connectionLink;
  String? _initiatorServerMailboxId;
  bool _generatingLink = false;
  bool _pollingPeer = false;
  Timer? _pollTimer;
  String? _incomingRequestFrom;
  bool _peerAccepted = false;
  bool _isPeerDisconnected = false;
  StreamSubscription? _mailboxSubscription;

  @override
  void initState() {
    super.initState();
    _connectionService = ConnectionService(
      signalingBaseUrl: widget.signalingBaseUrl,
    );
    _createInitiatorLink();
  }

  @override
  void dispose() {
    _connectionService.dispose();
    _pollTimer?.cancel();
    _mailboxSubscription?.cancel();
    _webrtcManager?.dispose();
    super.dispose();
  }

  Future<void> _createInitiatorLink() async {
    setState(() => _generatingLink = true);
    try {
      final initResult = await _connectionService.initializeConnectionLocally();
      final link = _connectionService.generateConnectionLink(
        initResult.rendezvousId,
        initResult.secret,
      );

      final initResp = await _connectionService.sendConnectionInit(
        clientId: widget.backend.clientId ?? '',
        sessionToken: widget.backend.sessionToken ?? '',
        rendezvousId: initResult.rendezvousId,
      );
      final serverMailboxId = initResp['mailbox_id'] as String?;

      if (serverMailboxId != null) {
        _initiatorServerMailboxId = serverMailboxId;
        _startListeningForPeer(serverMailboxId);
      }

      setState(() {
        _initiatorResult = initResult;
        _connectionLink = link;
        _generatingLink = false;
      });
    } catch (e) {
      setState(() => _generatingLink = false);
      _showSnackBar('Error: $e');
    }
  }

  void _startListeningForPeer(String mailboxId) {
    _mailboxSubscription?.cancel();
    setState(() => _pollingPeer = true);

    _mailboxSubscription = _connectionService.subscribeMailbox(mailboxId: mailboxId).listen((evt) {
      if (!_peerAccepted && _incomingRequestFrom == null) {
        setState(() {
          _pollingPeer = false;
          _incomingRequestFrom = evt['from_mailbox_id'] as String?;
        });
        _showIncomingDialog();
      } else if (_peerAccepted) {
        _handleIncomingSignal(evt);
      }
    }, onError: (_) {
      setState(() => _pollingPeer = false);
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
            children: [
              const SizedBox(height: 16),
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
                setState(() => _incomingRequestFrom = null);
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF19231a),
              ),
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  _peerAccepted = true;
                  _incomingRequestFrom = null;
                });
                _startWebRTCHandshake();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFcc3f0c),
                foregroundColor: const Color(0xFFffffff),
              ),
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
  }

  void _handleIncomingSignal(Map<String, dynamic> msg) async {
    final payloadB64 = msg['ciphertext_b64'] as String?;
    if (payloadB64 == null || payloadB64.isEmpty) return;

    try {
      final decryptedBytes = await rust_connection.connectionDecrypt(
        keyHex: _initiatorResult!.kSig,
        ciphertextB64: payloadB64,
      );
      final decoded = utf8.decode(decryptedBytes);
      print('Initiator: Received Signal: $decoded');
      final signalingMsg = SignalingMessage.fromJsonString(decoded);

      if (signalingMsg.type == 'answer') {
        print('Initiator: Processing Answer...');
        final answer = RTCSessionDescription(
          signalingMsg.data['sdp'] as String,
          signalingMsg.data['type'] as String,
        );
        await _webrtcManager!.setRemoteAnswer(answer);
      } else if (signalingMsg.type == 'ice') {
        print('Initiator: Processing ICE Candidate...');
        final candidate = RTCIceCandidate(
          signalingMsg.data['candidate'] as String,
          signalingMsg.data['sdpMid'] as String,
          signalingMsg.data['sdpMLineIndex'] as int,
        );
        await _webrtcManager!.addIceCandidate(candidate);
      } else if (signalingMsg.type == 'disconnect') {
        print('Initiator: Peer disconnected');
        _showSnackBar('Peer has disconnected.');
        await _webrtcManager?.dispose();
        setState(() {
          _webrtcManager = null;
          _webrtcState = null;
          _isPeerDisconnected = true;
        });
      }
    } catch (e) {
      print('Initiator: Error handling signal: $e');
    }
  }

  Future<void> _startWebRTCHandshake() async {
    try {
      _webrtcManager = WebRTCManager();
      await _webrtcManager!.initialize();

      _webrtcManager!.onStateChange.listen((state) {
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
        (candidate) => _sendIceCandidate(candidate),
      );

      final offer = await _webrtcManager!.createOffer();
      print('Initiator: Created Offer');

      final offerMsg = SignalingMessage(
        type: 'offer',
        data: {'sdp': offer.sdp, 'type': offer.type},
      );
      final offerB64 = await rust_connection.connectionEncrypt(
        keyHex: _initiatorResult!.kSig,
        plaintext: utf8.encode(offerMsg.toJsonString()),
      );
      print('Initiator: Sending Offer...');
      await _connectionService.sendSignal(
        mailboxId: _initiatorServerMailboxId!,
        ciphertextB64: offerB64,
      );
    } catch (e) {
      print('Initiator: WebRTC Error: $e');
      _showSnackBar('WebRTC error: $e');
    }
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    final iceMsg = SignalingMessage(
      type: 'ice',
      data: {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    );
    final iceB64 = await rust_connection.connectionEncrypt(
      keyHex: _initiatorResult!.kSig,
      plaintext: utf8.encode(iceMsg.toJsonString()),
    );
    await _connectionService.sendSignal(
      mailboxId: _initiatorServerMailboxId!,
      ciphertextB64: iceB64,
    );
  }

  Future<void> _sendTestMessage() async {
    try {
      await _webrtcManager?.sendMessage('Hello from initiator!');
      _showSnackBar('Message sent');
    } catch (e) {
      _showSnackBar('Send failed: $e');
    }
  }

  Future<void> _copyLink() async {
    if (_connectionLink == null) return;
    await Clipboard.setData(ClipboardData(text: _connectionLink!));
    _showSnackBar('Link copied');
  }

  Future<void> _shareLink() async {
    if (_connectionLink == null) return;
    await Share.share(_connectionLink!, subject: 'P2P Connection Link');
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
    if (_initiatorResult == null || _initiatorServerMailboxId == null) return;
    try {
      final msg = SignalingMessage(type: 'disconnect', data: {});
      final encryptedB64 = await rust_connection.connectionEncrypt(
        keyHex: _initiatorResult!.kSig,
        plaintext: utf8.encode(msg.toJsonString()),
      );
      await _connectionService.sendSignal(
        mailboxId: _initiatorServerMailboxId!,
        ciphertextB64: encryptedB64,
      );
    } catch (e) {
      print('Error sending disconnect signal: $e');
    }
  }

  Future<bool> _showExitConfirmation() async {
    if (_webrtcState != RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
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
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFd8cbc7),
        appBar: AppBar(
        title: const Text(
          'Create Connection',
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
            if (_generatingLink)
              const Center(child: CircularProgressIndicator())
            else if (_connectionLink != null && !_peerAccepted) ...[
              const Text(
                'Share this with your peer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Center(
                child: QrImageView(
                  data: _connectionLink!,
                  version: QrVersions.auto,
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Connection Link',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _connectionLink!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _copyLink,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy Link'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _shareLink,
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
              if (_initiatorResult != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: const Color(0xFFffffff),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Verification Code',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF19231a),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _initiatorResult!.sas.substring(0, 16),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            letterSpacing: 2,
                            color: Color(0xFFcc3f0c),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Compare this with your peer',
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF19231a).withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_pollingPeer) ...[
                const SizedBox(height: 24),
                Card(
                  color: const Color(0xFFffffff),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFcc3f0c),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'Waiting for peer...',
                          style: TextStyle(color: Color(0xFF19231a)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ] else if (_peerAccepted) ...[
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
                ElevatedButton.icon(
                  onPressed: _sendTestMessage,
                  icon: const Icon(Icons.send),
                  label: const Text('Send Test Message'),
                ),
                if (_receivedMessage != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: const Color(0xFFffffff),
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
