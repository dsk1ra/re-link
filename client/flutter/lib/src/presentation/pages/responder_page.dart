import 'dart:async';
import 'dart:convert';

import 'package:application/src/features/file_transfer/file_transfer_service.dart';
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
import 'package:application/src/features/pairing/domain/signaling_message.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:application/src/rust/api/connection.dart' as rust_connection;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// Responder screen - joins using connection link
class ResponderPage extends StatefulWidget {
  final String signalingBaseUrl;
  final SignalingBackend backend;
  final String? initialToken;
  final List<Map<String, dynamic>>? iceServers;

  const ResponderPage({
    super.key,
    required this.signalingBaseUrl,
    required this.backend,
    this.initialToken,
    this.iceServers,
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
  static const Duration _handshakeTimeout = Duration(seconds: 12);

  late ConnectionService _connectionService;
  WebRTCManager? _webrtcManager;
  FileTransferService? _fileTransferService;
  StreamSubscription<FileTransferState>? _fileTransferStateSubscription;
  final rtc.RTCVideoRenderer _remoteRenderer = rtc.RTCVideoRenderer();
  StreamSubscription<rtc.MediaStream>? _remoteStreamSubscription;

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
  bool _hasPendingIncomingFile = false;
  bool _isFileTransferSheetOpen = false;
  late final SessionControlProtocol _sessionControlProtocol;
  late final SerialTaskQueue<RTCIceCandidate> _iceCandidateQueue;
  late final SerialTaskQueue<Map<String, dynamic>> _signalQueue;
  Timer? _handshakeTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _connectionService = ConnectionService(
      signalingBaseUrl: widget.signalingBaseUrl,
    );
    _sessionControlProtocol = SessionControlProtocol(
      log: _log,
      sendPing: (ts) async {
        await _webrtcManager?.sendPing(ts);
      },
      sendSessionClosed: ({required String id, String? reason}) async {
        await _webrtcManager?.sendSessionClosed(id: id, reason: reason);
      },
      onHeartbeatTimeout: _handlePeerSessionClosed,
    );
    _iceCandidateQueue = SerialTaskQueue<RTCIceCandidate>(
      processor: (candidate) async {
        await _sendIceCandidate(candidate);
      },
      onError: (error, _) {
        final connected =
            _webrtcState ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected;
        if (error is MailboxNotFoundException &&
            (_signalingClosed || connected)) {
          _log.fine(
            'Ignoring stale mailbox ICE send after signaling closed: '
            '${error.mailboxId}',
          );
          return;
        }
        _log.warning('Queued ICE candidate send failed: $error');
      },
    );
    _signalQueue = SerialTaskQueue<Map<String, dynamic>>(
      processor: _handleIncomingSignal,
      onError: (_, _) {
        _log.warning('Queued signal processing failed');
      },
    );
    unawaited(_initRemoteRenderer());
    // ...
  }

  Future<void> _initRemoteRenderer() async {
    await _remoteRenderer.initialize();
  }

  Future<void> _attachRemoteStream(rtc.MediaStream stream) async {
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
      _disposeFileTransferService();
      _webrtcManager = WebRTCManager(
        connectionId: _responderMailboxId!,
        iceServers: widget.iceServers,
      );
      await _webrtcManager!.initialize();
      _attachFileTransferService(_webrtcManager!);

      _remoteStreamSubscription?.cancel();
      _remoteStreamSubscription = _webrtcManager!.onRemoteStream.listen((
        stream,
      ) {
        unawaited(_attachRemoteStream(stream));
      });

      final existingStream = _webrtcManager!.remoteStream;
      if (existingStream != null) {
        await _attachRemoteStream(existingStream);
      }

      _webrtcManager!.onStateChange.listen((state) {
        setState(() => _webrtcState = state);
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _cancelHandshakeTimeout();
          _closeSignalingAfterConnect();
          _sessionControlProtocol.startHeartbeat();
        }
      });

      _webrtcManager!.onRenegotiationOffer.listen((offer) {
        unawaited(_handleIncomingRenegotiationOffer(offer));
      });
      _webrtcManager!.onRenegotiationAnswer.listen((answer) {
        unawaited(_webrtcManager?.setRemoteAnswer(answer));
      });
      _webrtcManager!.onRenegotiationIceCandidate.listen((candidate) {
        unawaited(_webrtcManager?.addIceCandidate(candidate));
      });
      _webrtcManager!.onFileTransferRequested.listen((_) {
        unawaited(_handleIncomingFileTransferRequest());
      });
      _webrtcManager!.onScreenShareStopped.listen((_) {
        _detachRemoteStream();
        _showSnackBar('Host stopped sharing screen');
      });
      _webrtcManager!.onPeerSessionClosed.listen((_) {
        unawaited(_handlePeerSessionClosed());
      });
      _webrtcManager!.onSessionClosedAck.listen(
        _sessionControlProtocol.handleSessionClosedAck,
      );
      _webrtcManager!.onPong.listen((_) {
        _sessionControlProtocol.handlePong();
      });

      _webrtcManager!.onIceCandidate.listen((candidate) {
        if (_signalingClosed) {
          unawaited(_webrtcManager!.sendRenegotiationIce(candidate));
        } else {
          _iceCandidateQueue.enqueue(candidate);
        }
      });

      // Listen for mailbox history and new messages over the same stream.
      _startListeningForSignals();
    } catch (e) {
      _cancelHandshakeTimeout();
      await _webrtcManager?.dispose();
      _disposeFileTransferService();
      _detachRemoteStream();
      if (!mounted) return;

      final isRecoverableRendezvousError = _isRendezvousStatusError(e);
      setState(() {
        _webrtcManager = null;
        _webrtcState = null;
        _joined = false;
        _responderMailboxId = null;
        if (isRecoverableRendezvousError) {
          _joinError =
              'Link expired or invalid. Request a new connection link.';
        }
      });

      _showSnackBar(
        isRecoverableRendezvousError
            ? 'Link expired or invalid. Please request a new link.'
            : 'WebRTC error: $e',
      );
    }
  }

  void _cancelHandshakeTimeout() {
    _handshakeTimeoutTimer?.cancel();
    _handshakeTimeoutTimer = null;
  }

  void _startHandshakeTimeout() {
    _cancelHandshakeTimeout();
    _handshakeTimeoutTimer = Timer(_handshakeTimeout, () async {
      if (!mounted) return;
      final isConnected =
          _webrtcState ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      if (!_joined || isConnected) return;

      _log.warning('Responder handshake timed out');
      await _mailboxSubscription?.cancel();
      _mailboxSubscription = null;
      await _webrtcManager?.dispose();
      _disposeFileTransferService();
      _detachRemoteStream();

      if (!mounted) return;
      setState(() {
        _webrtcManager = null;
        _webrtcState = null;
        _joined = false;
        _responderMailboxId = null;
        _joinError =
            'Connection timed out. Ask the host for a fresh link and try again.';
      });
      _showSnackBar('Connection timed out. Please request a new link.');
    });
  }

  bool _isRendezvousStatusError(Object error) {
    final message = error.toString();
    return message.contains('404') ||
        message.contains('409') ||
        message.contains('410');
  }

  StreamSubscription? _mailboxSubscription;

  @override
  void dispose() {
    _cancelHandshakeTimeout();
    _connectionService.dispose();
    _tokenController.dispose();
    _mailboxSubscription?.cancel();
    _remoteStreamSubscription?.cancel();
    _sessionControlProtocol.dispose();
    _iceCandidateQueue.dispose();
    _signalQueue.dispose();
    _disposeFileTransferService();
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

      _startHandshakeTimeout();
      await _startWebRTCHandshake();
    } catch (e) {
      _cancelHandshakeTimeout();
      setState(() {
        _joiningConnection = false;
        _joinError = e.toString();
      });
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
        final answerB64 = rust_connection.connectionEncrypt(
          keyHex: _kSig!,
          plaintext: utf8.encode(answerMsg.toJsonString()),
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
      } else if (signalingMsg.type == 'disconnect') {
        _showSnackBar('Peer has disconnected.');
        _detachRemoteStream();
        await _webrtcManager?.dispose();
        _disposeFileTransferService();
        setState(() {
          _webrtcManager = null;
          _webrtcState = null;
          _isPeerDisconnected = true;
        });
      }
    } catch (_) {
      _log.warning('Responder signal handling failed');
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
    try {
      await _connectionService.sendSignal(
        mailboxId: _responderMailboxId!,
        ciphertextB64: iceB64,
      );
    } on MailboxNotFoundException {
      final connected =
          _webrtcState ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      if (_signalingClosed || connected) {
        _signalingClosed = true;
        _iceCandidateQueue.clear();
        await _mailboxSubscription?.cancel();
        _mailboxSubscription = null;
        return;
      }
      rethrow;
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleIncomingFileTransferRequest() async {
    if (!mounted || _webrtcManager == null || _fileTransferService == null) {
      return;
    }

    await _fileTransferService!.syncNow();
    await _openFileTransferSheet(autoOpened: true);
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
    } catch (_) {
      _log.warning('Signaling mailbox cleanup failed');
    }
  }

  Future<void> _handlePeerSessionClosed() async {
    _cancelHandshakeTimeout();
    _showSnackBar('Peer has disconnected.');
    _sessionControlProtocol.stopHeartbeat();
    _detachRemoteStream();
    await _webrtcManager?.dispose();
    _disposeFileTransferService();
    setState(() {
      _webrtcManager = null;
      _webrtcState = null;
      _isPeerDisconnected = true;
    });
  }

  void _attachFileTransferService(WebRTCManager manager) {
    _fileTransferStateSubscription?.cancel();
    _fileTransferService?.dispose();

    final transferService = FileTransferService(manager);
    _fileTransferService = transferService;
    _fileTransferStateSubscription = transferService.onStateChange.listen(
      _handleFileTransferState,
    );
  }

  void _disposeFileTransferService() {
    _fileTransferStateSubscription?.cancel();
    _fileTransferStateSubscription = null;
    _fileTransferService?.dispose();
    _fileTransferService = null;
    if (mounted && _hasPendingIncomingFile) {
      setState(() {
        _hasPendingIncomingFile = false;
      });
    } else {
      _hasPendingIncomingFile = false;
    }
  }

  void _handleFileTransferState(FileTransferState state) {
    final hasPendingOffer = state.status == TransferStatus.offered;
    final shouldOpenSheet = hasPendingOffer && !_hasPendingIncomingFile;

    if (mounted && _hasPendingIncomingFile != hasPendingOffer) {
      setState(() {
        _hasPendingIncomingFile = hasPendingOffer;
      });
    } else {
      _hasPendingIncomingFile = hasPendingOffer;
    }

    if (shouldOpenSheet && mounted) {
      unawaited(_openFileTransferSheet(autoOpened: true));
    }
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
    } catch (_) {
      _log.warning('Disconnect signal failed');
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
    await _webrtcManager?.sendRenegotiationAnswer(answer);
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
              ? rtc.RTCVideoView(
                  _remoteRenderer,
                  objectFit:
                      rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
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

  Future<void> _openFileTransferSheet({bool autoOpened = false}) async {
    if (_webrtcManager == null || _fileTransferService == null) return;
    if (_isFileTransferSheetOpen) return;

    if (!autoOpened && _hasPendingIncomingFile) {
      setState(() {
        _hasPendingIncomingFile = false;
      });
    }

    _isFileTransferSheetOpen = true;
    await showSessionFileTransferSheet(
      context: context,
      webrtcManager: _webrtcManager!,
      fileTransferService: _fileTransferService!,
    );

    _isFileTransferSheetOpen = false;
    if (!mounted) return;
    final state = _fileTransferService?.currentState;
    final hasPendingOffer = state?.status == TransferStatus.offered;
    if (_hasPendingIncomingFile != hasPendingOffer) {
      setState(() {
        _hasPendingIncomingFile = hasPendingOffer;
      });
    }
  }
}
