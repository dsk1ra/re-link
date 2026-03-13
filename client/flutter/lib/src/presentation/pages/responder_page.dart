import 'dart:async';
import 'dart:convert';

import 'package:application/src/features/session/application/serial_task_queue.dart';
import 'package:application/src/features/session/application/session_control_protocol.dart';
import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_card.dart';
import 'package:application/src/presentation/widgets/session_connection_badge.dart';
import 'package:application/src/presentation/widgets/session_file_transfer_sheet.dart';
import 'package:application/src/presentation/widgets/session_menu_overlay.dart';
import 'package:application/src/presentation/widgets/session_status_views.dart';
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
  late final SessionControlProtocol _sessionControlProtocol;
  late final SerialTaskQueue<RTCIceCandidate> _iceCandidateQueue;
  late final SerialTaskQueue<Map<String, dynamic>> _signalQueue;

  @override
  void initState() {
    super.initState();
    _connectionService = ConnectionService(
      signalingBaseUrl: widget.signalingBaseUrl,
    );
    _sessionControlProtocol = SessionControlProtocol(
      log: _log,
      sendControlMessage: (message) async {
        await _webrtcManager?.sendControlMessage(message);
      },
      onRenegotiationOffer: _handleIncomingRenegotiationOffer,
      onRenegotiationAnswer: (answer) async {
        await _webrtcManager?.setRemoteAnswer(answer);
      },
      onIceCandidate: (candidate) async {
        await _webrtcManager?.addIceCandidate(candidate);
      },
      onPeerSessionClosed: _handlePeerSessionClosed,
      onScreenShareStopped: () {
        _detachRemoteStream();
        _showSnackBar('Host stopped sharing screen');
      },
      showMessage: _showSnackBar,
    );
    _iceCandidateQueue = SerialTaskQueue<RTCIceCandidate>(
      processor: (candidate) async {
        await _sendIceCandidate(candidate);
        await Future.delayed(const Duration(milliseconds: 100));
      },
      onError: (error, _) {
        _log.warning('Error sending queued ICE candidate: $error');
      },
    );
    _signalQueue = SerialTaskQueue<Map<String, dynamic>>(
      processor: _handleIncomingSignal,
      onError: (error, _) {
        _log.warning('Error processing signal queue: $error');
      },
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
          _sessionControlProtocol.startHeartbeat();
        }
      });

      _webrtcManager!.onMessage.listen(_handleControlMessage);

      _webrtcManager!.onIceCandidate.listen((candidate) {
        if (_signalingClosed) {
          unawaited(_sendDataChannelIce(candidate));
        } else {
          _iceCandidateQueue.enqueue(candidate);
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

  StreamSubscription? _mailboxSubscription;

  @override
  void dispose() {
    _connectionService.dispose();
    _tokenController.dispose();
    _mailboxSubscription?.cancel();
    _remoteStreamSubscription?.cancel();
    _sessionControlProtocol.dispose();
    _iceCandidateQueue.dispose();
    _signalQueue.dispose();
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
          _signalQueue.enqueue(msg);
        });
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
    unawaited(_sessionControlProtocol.handleMessage(message));
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
    _sessionControlProtocol.stopHeartbeat();
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
      await _sessionControlProtocol.sendSessionClosedMessage();
    }
    return result ?? false;
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
    final String label = failed
        ? 'Disconnected'
        : (connected ? 'Connected' : _webrtcStateText());

    return SessionConnectionBadge(
      label: label,
      tone: failed
          ? SessionConnectionBadgeTone.error
          : (connected
                ? SessionConnectionBadgeTone.connected
                : SessionConnectionBadgeTone.warning),
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
    if (_isPeerDisconnected) {
      return SessionDisconnectedView(
        onReturnHome: () => Navigator.of(context).pop(),
      );
    }

    if (_webrtcState !=
        RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      return const SessionConnectingView(message: 'Establishing connection...');
    }

    return Stack(
      fit: StackFit.expand,
      children: [
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
            child: SessionMenuOverlay(
              width: _floatingMenuWidth,
              height: _menuOverlayHeight,
              isOpen: _showSessionMenu,
              onToggle: () {
                setState(() => _showSessionMenu = !_showSessionMenu);
              },
              handleIconSize: _menuHandleIconSize,
              closedTop: _menuHandleClosedTop,
              openTop: _menuHandleOpenTop,
              child: _buildFloatingMenu(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingMenu() {
    return SessionMenuCard(
      width: _floatingMenuWidth,
      cornerRadius: _floatingMenuCornerRadius,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          SessionMenuAction(
            icon: Icons.swap_horiz,
            label: 'Files',
            iconSize: _floatingMenuIconSize,
            labelFontSize: _floatingMenuLabelFontSize,
            onPressed: _openFileTransferSheet,
          ),
          SessionMenuAction(
            icon: Icons.call_end,
            label: 'Disconnect',
            iconSize: _floatingMenuIconSize,
            labelFontSize: _floatingMenuLabelFontSize,
            color: AppColors.error,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  // ─── File transfer bottom sheet ───────────────────────────────────────────

  void _openFileTransferSheet() {
    if (_webrtcManager == null) return;
    showSessionFileTransferSheet(
      context: context,
      webrtcManager: _webrtcManager!,
    );
  }
}
