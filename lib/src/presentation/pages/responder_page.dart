import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:application/src/features/pairing/data/connection_service.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
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
  late ConnectionService _connectionService;
  WebRTCManager? _webrtcManager;

  RTCPeerConnectionState? _webrtcState;
  String? _receivedMessage;

  final TextEditingController _tokenController = TextEditingController();
  String? _responderMailboxId;
  bool _joiningConnection = false;
  String? _joinError;
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    _connectionService = ConnectionService(
      signalingBaseUrl: widget.signalingBaseUrl,
    );
    if (widget.initialToken != null) {
      _tokenController.text = widget.initialToken!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _joinWithToken());
    }
  }

  @override
  void dispose() {
    _connectionService.dispose();
    _tokenController.dispose();
    _webrtcManager?.dispose();
    super.dispose();
  }

  Future<void> _joinWithToken() async {
    final input = _tokenController.text.trim();
    if (input.isEmpty) {
      _showSnackBar('Enter connection token');
      return;
    }

    String token = input;
    try {
      final uri = Uri.parse(input);
      if (uri.hasQuery && uri.queryParameters.containsKey('token')) {
        token = uri.queryParameters['token']!;
      }
    } catch (_) {}

    setState(() {
      _joiningConnection = true;
      _joinError = null;
    });

    try {
      final joinResult = await _connectionService.joinConnection(
        tokenB64: token,
      );
      final mailboxId = joinResult['mailbox_id'] as String;

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

      _startPollingForWebRTCMessages();
    } catch (e) {
      _showSnackBar('WebRTC error: $e');
    }
  }

  void _startPollingForWebRTCMessages() {
    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_webrtcState ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        timer.cancel();
        return;
      }

      try {
        final messages = await _connectionService.fetchMessages(
          mailboxId: _responderMailboxId!,
        );

        for (final msg in messages) {
          final payloadB64 = msg['ciphertext_b64'] as String?;
          if (payloadB64 == null || payloadB64.isEmpty) continue;

          try {
            final normalized = base64Url.normalize(payloadB64);
            final decoded = utf8.decode(base64Url.decode(normalized));
            final signalingMsg = SignalingMessage.fromJsonString(decoded);

            if (signalingMsg.type == 'offer') {
              final offer = RTCSessionDescription(
                signalingMsg.data['sdp'] as String,
                signalingMsg.data['type'] as String,
              );
              final answer = await _webrtcManager!.createAnswer(offer);

              final answerMsg = SignalingMessage(
                type: 'answer',
                data: {'sdp': answer.sdp, 'type': answer.type},
              );
              final answerB64 = base64Url.encode(
                utf8.encode(answerMsg.toJsonString()),
              );
              await _connectionService.sendSignal(
                mailboxId: _responderMailboxId!,
                ciphertextB64: answerB64,
              );
            } else if (signalingMsg.type == 'ice') {
              final candidate = RTCIceCandidate(
                signalingMsg.data['candidate'] as String,
                signalingMsg.data['sdpMid'] as String,
                signalingMsg.data['sdpMLineIndex'] as int,
              );
              await _webrtcManager!.addIceCandidate(candidate);
            }
          } catch (_) {}
        }
      } catch (_) {}
    });
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
    final iceB64 = base64Url.encode(utf8.encode(iceMsg.toJsonString()));
    await _connectionService.sendSignal(
      mailboxId: _responderMailboxId!,
      ciphertextB64: iceB64,
    );
  }

  Future<void> _sendTestMessage() async {
    try {
      await _webrtcManager?.sendMessage('Hello from responder!');
      _showSnackBar('Message sent');
    } catch (e) {
      _showSnackBar('Send failed: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _webrtcStateText() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    borderSide: BorderSide(color: Color(0xFFcc3f0c), width: 2),
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
                  ).withOpacity(0.3),
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
                        _webrtcState ==
                                RTCPeerConnectionState
                                    .RTCPeerConnectionStateConnected
                            ? Icons.check_circle
                            : Icons.sync,
                        size: 64,
                        color:
                            _webrtcState ==
                                RTCPeerConnectionState
                                    .RTCPeerConnectionStateConnected
                            ? const Color(0xFFcc3f0c)
                            : const Color(0xFF19231a),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _webrtcState ==
                                RTCPeerConnectionState
                                    .RTCPeerConnectionStateConnected
                            ? 'Connected!'
                            : 'Establishing Connection...',
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
                    ],
                  ),
                ),
              ),
              if (_webrtcState ==
                  RTCPeerConnectionState.RTCPeerConnectionStateConnected) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _sendTestMessage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFcc3f0c),
                    foregroundColor: const Color(0xFFffffff),
                  ),
                  icon: const Icon(Icons.send),
                  label: const Text('Send Test Message'),
                ),
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
    );
  }
}
