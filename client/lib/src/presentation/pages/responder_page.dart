import 'dart:async';
import 'dart:convert';

import 'package:application/src/features/file_transfer/file_transfer_widget.dart';
import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_card.dart';
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

  // ─── Layout / style constants ────────────────────────────────────────────
  static const double _maxFormWidth = 520;
  static const double _formTitleFontSize = 20;
  static const double _joinButtonVerticalPadding = 16;
  static const double _joinSpinnerSize = 20;
  static const double _menuHandleIconSize = 45;
  static const double _floatingMenuWidth = 220;
  static const double _floatingMenuIconSize = 22;
  static const double _floatingMenuLabelFontSize = 11;
  static const double _floatingMenuTopPadding = 10;
  static const double _floatingMenuCornerRadius = 14;
  static const double _menuHandleClosedTop = 0;
  static const double _menuHandleOpenTop = 108;
  static const double _menuOverlayHeight = 170;
  static const double _dragHandleWidth = 40;
  static const double _dragHandleHeight = 4;
  static const double _dragHandleBorderRadius = 2;
  static const double _sheetHeaderIconSize = 18;
  static const double _sheetHeaderIconGap = AppSpacing.sm;

  late ConnectionService _connectionService;
  WebRTCManager? _webrtcManager;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  StreamSubscription<MediaStream>? _remoteStreamSubscription;

  RTCPeerConnectionState? _webrtcState;

  final TextEditingController _tokenController = TextEditingController();
  String? _responderMailboxId;
  String? _kSig; // Session encryption key
  bool _joiningConnection = false;
  String? _joinError;
  bool _joined = false;
  bool _isPeerDisconnected = false;
  bool _signalingClosed = false;
  bool _showSessionMenu = false;
  Timer? _heartbeatTimer;
  DateTime? _lastPongAt;
  Timer? _sessionClosedAckTimer;
  String? _sessionClosedId;
  bool _sessionClosedAcked = false;

  final List<RTCIceCandidate> _iceCandidateQueue = [];
  bool _isSendingIce = false;

  @override
  void initState() {
    super.initState();
    _connectionService = ConnectionService(
      signalingBaseUrl: widget.signalingBaseUrl,
    );
    unawaited(_initRemoteRenderer());
    // ...
  }

  Future<void> _initRemoteRenderer() async {
    await _remoteRenderer.initialize();
  }

  Future<void> _attachRemoteStream(MediaStream stream) async {
    _remoteRenderer.srcObject = stream;
    if (mounted) {
      setState(() {});
    }
  }

  void _detachRemoteStream() {
    _remoteRenderer.srcObject = null;
    if (mounted) {
      setState(() {});
    }
  }

  // ...

  Future<void> _startWebRTCHandshake() async {
    try {
      _webrtcManager = WebRTCManager();
      await _webrtcManager!.initialize();

      _remoteStreamSubscription?.cancel();
      _remoteStreamSubscription = _webrtcManager!.onRemoteStream.listen((
        stream,
      ) {
        _attachRemoteStream(stream);
      });

      final existingStream = _webrtcManager!.remoteStream;
      if (existingStream != null) {
        await _attachRemoteStream(existingStream);
      }

      _webrtcManager!.onStateChange.listen((state) {
        _log.info('Responder: State changed to $state');
        setState(() => _webrtcState = state);
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _closeSignalingAfterConnect();
          _startHeartbeat();
        }
      });

      _webrtcManager!.onMessage.listen(_handleControlMessage);

      _webrtcManager!.onIceCandidate.listen((candidate) {
        if (_signalingClosed) {
          unawaited(_sendDataChannelIce(candidate));
        } else {
          _queueIceCandidate(candidate);
        }
      });

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
    _remoteStreamSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _sessionClosedAckTimer?.cancel();
    _remoteRenderer.dispose();
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
    if (_signalingClosed) return;

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
        _detachRemoteStream();
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
    if (_signalingClosed) return;

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

  void _handleControlMessage(String message) {
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final type = decoded['type'];
      if (type == 'session_closed') {
        _sendSessionClosedAck(decoded['id']?.toString());
        _handlePeerSessionClosed();
        return;
      }
      if (type == 'session_closed_ack') {
        _handleSessionClosedAck(decoded['id']?.toString());
        return;
      }
      if (type == 'ping') {
        _sendPong(decoded['ts']?.toString());
        return;
      }
      if (type == 'pong') {
        _lastPongAt = DateTime.now();
        return;
      }
      if (type == 'webrtc_offer') {
        final data = (decoded['data'] as Map).cast<String, dynamic>();
        final offer = RTCSessionDescription(
          data['sdp'] as String,
          data['type'] as String,
        );
        unawaited(_handleIncomingRenegotiationOffer(offer));
        return;
      }
      if (type == 'webrtc_answer') {
        final data = (decoded['data'] as Map).cast<String, dynamic>();
        final answer = RTCSessionDescription(
          data['sdp'] as String,
          data['type'] as String,
        );
        unawaited(_webrtcManager?.setRemoteAnswer(answer));
        return;
      }
      if (type == 'webrtc_ice') {
        final data = (decoded['data'] as Map).cast<String, dynamic>();
        final candidate = RTCIceCandidate(
          data['candidate'] as String,
          data['sdpMid'] as String?,
          data['sdpMLineIndex'] as int?,
        );
        unawaited(_webrtcManager?.addIceCandidate(candidate));
        return;
      }
      if (type == 'screen_share_stopped') {
        _detachRemoteStream();
        _showSnackBar('Host stopped sharing screen');
        return;
      }
    } catch (_) {}

    _showSnackBar('Received: $message');
  }

  Future<void> _closeSignalingAfterConnect() async {
    if (_signalingClosed) return;
    final mailboxId = _responderMailboxId;
    if (mailboxId == null) return;

    _signalingClosed = true;
    _iceCandidateQueue.clear();
    await _mailboxSubscription?.cancel();
    _mailboxSubscription = null;

    try {
      await _connectionService.closeConnection(mailboxId: mailboxId);
    } catch (e) {
      _log.warning('Failed to close signaling mailbox: $e');
    }
  }

  Future<void> _handlePeerSessionClosed() async {
    _log.info('Responder: Peer session closed over WebRTC');
    _showSnackBar('Peer has disconnected.');
    _stopHeartbeat();
    _detachRemoteStream();
    await _webrtcManager?.dispose();
    setState(() {
      _webrtcManager = null;
      _webrtcState = null;
      _isPeerDisconnected = true;
    });
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
    if (_signalingClosed) return;
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
          'You are currently in an active session. Disconnecting will end the connection for both parties.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            child: const Text('Keep Connected'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _sendDisconnectSignal();
      await _sendSessionClosedMessage();
    }
    return result ?? false;
  }

  Future<void> _sendSessionClosedMessage() async {
    try {
      _sessionClosedId = DateTime.now().millisecondsSinceEpoch.toString();
      _sessionClosedAcked = false;
      _startSessionClosedAckTimer();
      final msg = jsonEncode({
        'type': 'session_closed',
        'id': _sessionClosedId,
        'reason': 'local_disconnect',
      });
      await _webrtcManager?.sendControlMessage(msg);
    } catch (e) {
      _log.warning('Error sending session closed message: $e');
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _lastPongAt = DateTime.now();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final last = _lastPongAt;
      if (last != null &&
          DateTime.now().difference(last) > const Duration(seconds: 15)) {
        _handleHeartbeatTimeout();
        return;
      }

      _sendPing();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _handleHeartbeatTimeout() {
    _log.warning('Responder: Heartbeat timeout, closing session');
    _stopHeartbeat();
    unawaited(_handlePeerSessionClosed());
  }

  Future<void> _sendPing() async {
    try {
      final msg = jsonEncode({
        'type': 'ping',
        'ts': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      await _webrtcManager?.sendControlMessage(msg);
    } catch (e) {
      _log.warning('Error sending ping: $e');
    }
  }

  Future<void> _sendPong(String? ts) async {
    try {
      final msg = jsonEncode({'type': 'pong', 'ts': ts});
      await _webrtcManager?.sendControlMessage(msg);
    } catch (e) {
      _log.warning('Error sending pong: $e');
    }
  }

  void _startSessionClosedAckTimer() {
    _sessionClosedAckTimer?.cancel();
    _sessionClosedAckTimer = Timer(const Duration(seconds: 5), () {
      if (_sessionClosedAcked) return;
      _log.warning('Responder: Session closed ack not received');
    });
  }

  void _handleSessionClosedAck(String? id) {
    if (_sessionClosedId == null || _sessionClosedId != id) return;
    _sessionClosedAcked = true;
    _sessionClosedAckTimer?.cancel();
  }

  Future<void> _sendSessionClosedAck(String? id) async {
    if (id == null) return;
    try {
      final msg = jsonEncode({'type': 'session_closed_ack', 'id': id});
      await _webrtcManager?.sendControlMessage(msg);
    } catch (e) {
      _log.warning('Error sending session closed ack: $e');
    }
  }

  Future<void> _handleIncomingRenegotiationOffer(
    RTCSessionDescription offer,
  ) async {
    if (_webrtcManager == null) return;
    final answer = await _webrtcManager!.createAnswer(offer);
    final msg = jsonEncode({
      'type': 'webrtc_answer',
      'data': {'sdp': answer.sdp, 'type': answer.type},
    });
    await _webrtcManager?.sendControlMessage(msg);
  }

  Future<void> _sendDataChannelIce(RTCIceCandidate candidate) async {
    final msg = jsonEncode({
      'type': 'webrtc_ice',
      'data': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
    await _webrtcManager?.sendControlMessage(msg);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isConnected =
        _webrtcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showExitConfirmation();
        if (!context.mounted) return;
        if (shouldPop) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: isConnected
            ? null
            : AppBar(
                title: Text(
                  'Join Connection',
                  style: AppTypography.title(
                    size: AppUiMetrics.appBarTitleFontSize,
                  ),
                ),
                backgroundColor: AppColors.surface,
                elevation: 0,
                iconTheme: const IconThemeData(color: AppColors.textPrimary),
                actions: [
                  if (_joined) ...[
                    _buildConnectionBadge(),
                    const SizedBox(width: AppSpacing.md),
                  ],
                ],
              ),
        body: !_joined ? _buildJoinForm() : _buildConnectedLayout(),
      ),
    );
  }

  // ─── AppBar badge ─────────────────────────────────────────────────────────

  Widget _buildConnectionBadge() {
    final connected =
        !_isPeerDisconnected &&
        _webrtcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    final failed = _isPeerDisconnected;
    final Color dot = failed
        ? AppColors.error
        : (connected ? AppColors.success : AppColors.warning);
    final String label = failed
        ? 'Disconnected'
        : (connected ? 'Connected' : _webrtcStateText());

    return Container(
      padding: AppUiMetrics.badgePadding,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppUiMetrics.badgeBorderRadius),
        border: Border.all(color: dot.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppUiMetrics.badgeDotSize,
            height: AppUiMetrics.badgeDotSize,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppUiMetrics.badgeDotGap),
          Text(
            label,
            style: AppTypography.body(
              size: AppUiMetrics.badgeFontSize,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Pre-join form ────────────────────────────────────────────────────────

  Widget _buildJoinForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxFormWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Enter connection link',
                style: AppTypography.title(size: _formTitleFontSize),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                controller: _tokenController,
                style: AppTypography.body(),
                decoration: InputDecoration(
                  labelText: 'Paste link or token',
                  labelStyle: AppTypography.body(color: AppColors.textMuted),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.outline),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  prefixIcon: const Icon(
                    Icons.link,
                    color: AppColors.textMuted,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: AppSpacing.base),
              ElevatedButton.icon(
                onPressed: _joiningConnection ? null : _joinWithToken,
                icon: _joiningConnection
                    ? const SizedBox(
                        width: _joinSpinnerSize,
                        height: _joinSpinnerSize,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  _joiningConnection ? 'Joining...' : 'Join Connection',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(
                    vertical: _joinButtonVerticalPadding,
                  ),
                ),
              ),
              if (_joinError != null) ...[
                const SizedBox(height: AppSpacing.base),
                AppCard(
                  variant: AppCardVariant.error,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Error',
                        style: AppTypography.body(
                          weight: FontWeight.w700,
                          color: AppColors.error,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(_joinError!, style: AppTypography.body()),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Connected layout ─────────────────────────────────────────────────────

  Widget _buildConnectedLayout() {
    // Case: peer disconnected
    if (_isPeerDisconnected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: AppCard(
            variant: AppCardVariant.error,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cancel,
                  size: AppUiMetrics.disconnectedIconSize,
                  color: AppColors.error,
                ),
                const SizedBox(height: AppSpacing.base),
                Text('Connection Ended', style: AppTypography.title()),
                const SizedBox(height: AppSpacing.base),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                  ),
                  child: const Text('Return to Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Case: still negotiating
    if (_webrtcState !=
        RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.lg),
            Text('Establishing connection...'),
          ],
        ),
      );
    }

    // Case: connected — immersive remote screen
    return Stack(
      fit: StackFit.expand,
      children: [
        // Remote video fills the whole area
        Container(
          color: AppColors.background,
          child: _remoteRenderer.srcObject != null
              ? RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                )
              : Center(
                  child: Text(
                    'Waiting for shared screen…',
                    style: AppTypography.body(color: AppColors.textMuted),
                  ),
                ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _buildConnectionBadge(),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: _floatingMenuTopPadding),
            child: _buildSlidingMenuOverlay(),
          ),
        ),
      ],
    );
  }

  // ─── Floating top menu (triangle handle + icon actions) ─────────────────

  Widget _buildSlidingMenuOverlay() {
    return SizedBox(
      width: _floatingMenuWidth,
      height: _menuOverlayHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              ignoring: !_showSessionMenu,
              child: AnimatedOpacity(
                opacity: _showSessionMenu ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: AnimatedSlide(
                  offset: _showSessionMenu
                      ? Offset.zero
                      : const Offset(0, -1.0),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOut,
                  child: _buildFloatingMenu(),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            top: _showSessionMenu ? _menuHandleOpenTop : _menuHandleClosedTop,
            left: 0,
            right: 0,
            child: Center(child: _buildMenuHandle()),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuHandle() {
    return GestureDetector(
      onTap: () => setState(() => _showSessionMenu = !_showSessionMenu),
      child: AnimatedRotation(
        turns: _showSessionMenu ? 0.5 : 0.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: Icon(
          Icons.expand_more,
          size: _menuHandleIconSize,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildFloatingMenu() {
    return Container(
      width: _floatingMenuWidth,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.md,
        AppSpacing.base,
        AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(_floatingMenuCornerRadius),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildFloatingMenuAction(
            icon: Icons.swap_horiz,
            label: 'Files',
            onPressed: _openFileTransferSheet,
          ),
          _buildFloatingMenuAction(
            icon: Icons.call_end,
            label: 'Disconnect',
            color: AppColors.error,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingMenuAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final actionColor = onPressed == null
        ? AppColors.textMuted.withValues(alpha: 0.6)
        : (color ?? AppColors.textPrimary);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: actionColor, size: _floatingMenuIconSize),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.body(
                size: _floatingMenuLabelFontSize,
                color: actionColor,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── File transfer bottom sheet ───────────────────────────────────────────

  void _openFileTransferSheet() {
    if (_webrtcManager == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        minChildSize: 0.25,
        maxChildSize: 0.85,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: _dragHandleWidth,
                    height: _dragHandleHeight,
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.outline,
                      borderRadius: BorderRadius.circular(
                        _dragHandleBorderRadius,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Icon(
                      Icons.swap_horiz,
                      color: AppColors.textMuted,
                      size: _sheetHeaderIconSize,
                    ),
                    const SizedBox(width: _sheetHeaderIconGap),
                    Text(
                      'File Transfer',
                      style: AppTypography.body(weight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FileTransferWidget(webrtcManager: _webrtcManager!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
