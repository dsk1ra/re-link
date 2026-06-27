import 'dart:async';
import 'dart:convert';

import 'package:application/src/features/file_transfer/file_transfer_service.dart';
import 'package:application/src/features/session/application/serial_task_queue.dart';
import 'package:application/src/features/session/application/session_control_protocol.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/presentation/widgets/app_card.dart';
import 'package:application/src/presentation/widgets/dot_grid_background.dart';
import 'package:application/src/presentation/widgets/handshake_animation.dart';
import 'package:application/src/presentation/widgets/session_connection_badge.dart';
import 'package:application/src/presentation/widgets/session_file_transfer_sheet.dart';
import 'package:application/src/presentation/widgets/session_menu_overlay.dart';
import 'package:application/src/presentation/widgets/session_status_views.dart';
import 'package:application/src/presentation/widgets/session_voice_dialog.dart';
import 'package:application/src/presentation/widgets/remote_input_capture.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:application/src/features/network/data/server_error.dart';
import 'package:application/src/features/pairing/data/connection_service.dart';
import 'package:application/src/features/pairing/domain/pairing_code.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/features/pairing/domain/signaling_message.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:application/src/presentation/widgets/texture_video_view.dart';
import 'package:application/src/rust/api/audio.dart' as rust_audio;
import 'package:application/src/rust/api/connection.dart' as rust_connection;

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
  static const double _menuHandleIconSize = 36;
  static const double _floatingMenuWidth = 280;
  static const double _floatingMenuIconSize = 20;
  static const double _floatingMenuLabelFontSize = 10;
  static const double _floatingMenuTopPadding = 10;
  static const double _menuHandleClosedTop = 0;
  static const double _menuHandleOpenTop = 108;
  static const double _menuOverlayHeight = 170;
  static const Duration _handshakeTimeout = Duration(seconds: 12);

  late ConnectionService _connectionService;
  late String _activeSignalingBaseUrl;
  WebRTCManager? _webrtcManager;
  FileTransferService? _fileTransferService;
  StreamSubscription<FileTransferState>? _fileTransferStateSubscription;
  bool _hasRemoteVideo = false;
  double? _remoteVideoWidth;
  double? _remoteVideoHeight;
  bool _remoteInputEnabled = false;

  RTCPeerConnectionState? _webrtcState;

  final TextEditingController _tokenController = TextEditingController();
  String? _responderMailboxId;
  String? _kSig; // Session encryption key
  String? _verificationCode;
  bool _joiningConnection = false;
  String? _joinError;
  bool _joined = false;
  bool _isPeerDisconnected = false;
  bool _signalingClosed = false;
  bool _showSessionMenu = true;
  bool _audioActive = false;
  bool _audioMuted = false;
  bool _startingAudio = false;
  String? _selectedAudioSourceId;
  bool _handshakeComplete = false;
  bool _hasPendingIncomingFile = false;
  bool _isFileTransferSheetOpen = false;
  late final SessionControlProtocol _sessionControlProtocol;
  late final SerialTaskQueue<RTCIceCandidate> _iceCandidateQueue;
  late final SerialTaskQueue<Map<String, dynamic>> _signalQueue;
  Timer? _handshakeTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _activeSignalingBaseUrl = widget.signalingBaseUrl;
    _connectionService = ConnectionService(
      signalingBaseUrl: _activeSignalingBaseUrl,
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
      onIceRestartRequested: () async {
        await _webrtcManager?.requestIceRestart();
      },
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
    // ...
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

      _webrtcManager!.onVideoFrameSize.listen((frame) {
        final w = frame.width.toDouble();
        final h = frame.height.toDouble();
        final needsRebuild =
            !_hasRemoteVideo || w != _remoteVideoWidth || h != _remoteVideoHeight;
        if (needsRebuild && mounted) {
          setState(() {
            _hasRemoteVideo = true;
            _remoteVideoWidth = w;
            _remoteVideoHeight = h;
          });
        }
      });

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
        if (mounted) {
          setState(() {
            _hasRemoteVideo = false;
            _remoteVideoWidth = null;
            _remoteVideoHeight = null;
            _remoteInputEnabled = false;
          });
        }
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
    _sessionControlProtocol.dispose();
    _iceCandidateQueue.dispose();
    _signalQueue.dispose();
    _disposeFileTransferService();
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

    setState(() {
      _kSig = null;
      _verificationCode = null;
      _joinError = null;
    });

    String token = input;
    String? secret;
    String? signalingBaseUrlFromLink;

    try {
      final uri = Uri.parse(input);
      if (uri.hasQuery && uri.queryParameters.containsKey('token')) {
        token = uri.queryParameters['token']!;
      }
      // Extract secret from fragment (e.g. #secret_hex)
      if (uri.hasFragment && uri.fragment.isNotEmpty) {
        secret = uri.fragment;
      }
      signalingBaseUrlFromLink = _extractSignalingBaseUrlFromJoinUri(uri);
    } catch (_) {}

    if (signalingBaseUrlFromLink != null &&
        signalingBaseUrlFromLink != _activeSignalingBaseUrl) {
      _connectionService.dispose();
      _activeSignalingBaseUrl = signalingBaseUrlFromLink;
      _connectionService = ConnectionService(
        signalingBaseUrl: _activeSignalingBaseUrl,
      );
    }

    // If we have no secret, we cannot derive keys for E2EE
    if (secret == null) {
      setState(() {
        _kSig = null;
        _verificationCode = null;
        _joinError = 'Invalid link: Missing security key (fragment)';
      });
      return;
    }

    try {
      final keys = rust_connection.connectionDeriveKeys(secretHex: secret);
      setState(() {
        _kSig = keys.kSig;
        _verificationCode = formatPairingCode(keys.sas);
        _joiningConnection = true;
        _joinError = null;
        _joined = false;
        _responderMailboxId = null;
      });

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
        _handshakeComplete = false;
      });

      _startHandshakeTimeout();
      await _startWebRTCHandshake();
    } on MailboxNotFoundException {
      _cancelHandshakeTimeout();
      setState(() {
        _joiningConnection = false;
        _joinError =
            'Link expired or invalid. Ask the host for a new connection link.';
      });
    } catch (e) {
      _cancelHandshakeTimeout();
      final classified = ServerError.classify(e);
      setState(() {
        _joiningConnection = false;
        _joinError = classified.userMessage;
      });
    }
  }

  String? _extractSignalingBaseUrlFromJoinUri(Uri uri) {
    if (!uri.hasScheme || uri.host.isEmpty) {
      return null;
    }

    final origin =
        '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    const joinPathSuffix = '/connection/join';
    final path = uri.path;

    if (path.endsWith(joinPathSuffix)) {
      final basePath = path.substring(0, path.length - joinPathSuffix.length);
      if (basePath.isEmpty || basePath == '/') {
        return origin;
      }
      return '$origin$basePath';
    }

    if (path.isEmpty || path == '/') {
      return origin;
    }

    return '$origin$path';
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
        final sdpMLineIndexValue = signalingMsg.data['sdpMLineIndex'];
        final candidate = RTCIceCandidate(
          signalingMsg.data['candidate'] as String,
          signalingMsg.data['sdpMid'] as String?,
          sdpMLineIndexValue is num ? sdpMLineIndexValue.toInt() : null,
        );
        await _webrtcManager!.addIceCandidate(candidate);
      } else if (signalingMsg.type == 'disconnect') {
        _showSnackBar('Peer has disconnected.');
        await _webrtcManager?.dispose();
        _disposeFileTransferService();
        setState(() {
          _webrtcManager = null;
          _webrtcState = null;
          _isPeerDisconnected = true;
          _audioActive = false;
          _audioMuted = false;
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

  // ─── Voice chat ───────────────────────────────────────────────────────────

  Future<void> _handleVoiceAction() async {
    final manager = _webrtcManager;
    if (manager == null) return;

    if (!_audioActive) {
      await _openVoiceDialog();
      return;
    }

    final muteNext = !_audioMuted;
    try {
      await manager.setAudioMuted(muteNext);
      if (!mounted) return;
      setState(() => _audioMuted = muteNext);
    } catch (e) {
      _log.warning('Microphone mute toggle failed: $e');
      _showSnackBar('Failed to ${muteNext ? 'mute' : 'unmute'} microphone');
    }
  }

  Future<void> _openVoiceDialog() async {
    final manager = _webrtcManager;
    if (manager == null) return;

    List<rust_audio.AudioSourceDto> sources;
    try {
      sources = await manager.listAudioSources();
    } catch (e) {
      _showSnackBar('Failed to list microphones');
      return;
    }
    if (!mounted) return;

    final result = await showSessionVoiceDialog(
      context: context,
      sources: sources,
      selectedSourceId: _selectedAudioSourceId,
      audioActive: _audioActive,
    );
    if (result == null || !mounted) return;

    switch (result.action) {
      case VoiceDialogAction.start:
        setState(() {
          _startingAudio = true;
          _selectedAudioSourceId = result.sourceId;
        });
        try {
          await manager.startAudioCapture(sourceId: result.sourceId);
          if (!mounted) return;
          setState(() {
            _audioActive = true;
            _audioMuted = false;
          });
        } catch (e) {
          _log.warning('Voice start failed: $e');
          _showSnackBar('Failed to start voice');
        } finally {
          if (mounted) setState(() => _startingAudio = false);
        }
      case VoiceDialogAction.apply:
        try {
          await manager.setAudioSource(result.sourceId);
          if (!mounted) return;
          setState(() => _selectedAudioSourceId = result.sourceId);
        } catch (e) {
          _showSnackBar('Failed to switch microphone');
        }
      case VoiceDialogAction.stop:
        try {
          await manager.stopAudioCapture();
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _audioActive = false;
          _audioMuted = false;
        });
    }
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
    await _webrtcManager?.dispose();
    _disposeFileTransferService();
    setState(() {
      _webrtcManager = null;
      _webrtcState = null;
      _isPeerDisconnected = true;
      _audioActive = false;
      _audioMuted = false;
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ACTIVE SESSION', style: AppTypography.eyebrow),
            const SizedBox(height: AppSpacing.sm),
            Text('End connection?', style: AppTypography.h2),
          ],
        ),
        content: Text(
          'Disconnecting ends the encrypted session for both parties. '
          'Session keys are discarded.',
          style: AppTypography.body.copyWith(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            child: const Text('KEEP CONNECTED'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('DISCONNECT'),
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
                title: const Text('JOIN CONNECTION'),
                actions: [
                  if (_joined) ...[
                    _buildConnectionBadge(),
                    const SizedBox(width: AppSpacing.md),
                  ],
                ],
              ),
        body: !_joined
            ? DotGridBackground(child: _buildJoinForm())
            : _buildConnectedLayout(),
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
              Text('RESPOND', style: AppTypography.eyebrow),
              const SizedBox(height: AppSpacing.sm),
              Text('Join a session', style: AppTypography.h1),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Paste the invite link you received. The security key in the '
                'link fragment never reaches the server.',
                style: AppTypography.body.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _tokenController,
                style: AppTypography.data,
                decoration: const InputDecoration(
                  hintText: 'Paste link or token',
                  prefixIcon: Icon(
                    LucideIcons.link,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                onPressed: _joiningConnection ? null : _joinWithToken,
                loading: _joiningConnection,
                label: _joiningConnection ? 'Joining' : 'Join connection',
              ),
              if (_verificationCode != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _buildVerificationCodeCard(
                  _verificationCode!,
                  'Read this code to the host before the session is accepted.',
                ),
              ],
              if (_joinError != null) ...[
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  emphasized: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'JOIN FAILED',
                            style: AppTypography.eyebrow.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(_joinError!, style: AppTypography.body),
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

  Widget _buildVerificationCodeCard(String code, String message) {
    return AppCard(
      eyebrow: 'Verify with peer',
      emphasized: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(code, style: AppTypography.displayData),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          ),
        ],
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

    final isConnected =
        _webrtcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    if (!isConnected || !_handshakeComplete) {
      return DotGridBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxFormWidth),
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  HandshakeAnimation(
                    connected: isConnected,
                    onFinished: () {
                      if (!mounted) return;
                      setState(() => _handshakeComplete = true);
                    },
                  ),
                  if (_verificationCode != null) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _buildVerificationCodeCard(
                      _verificationCode!,
                      'Keep this visible until the host confirms the same code.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: AppColors.background,
          child: _hasRemoteVideo && _webrtcManager != null
              ? RemoteInputCapture(
                  webrtcManager: _webrtcManager!,
                  sourceWidth: _remoteVideoWidth,
                  sourceHeight: _remoteVideoHeight,
                  enabled: _remoteInputEnabled,
                  child: TextureVideoView(
                    sourceWidth: _remoteVideoWidth,
                    sourceHeight: _remoteVideoHeight,
                  ),
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.ok,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'SESSION ACTIVE · VIEWER',
                            style: AppTypography.eyebrow.copyWith(
                              color: AppColors.ok,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Connected to host',
                        style: AppTypography.h2,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'The host has not started sharing their screen yet.\n'
                        'Use the menu to transfer files while you wait.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          if (_hasRemoteVideo)
            Flexible(
              child: SessionMenuAction(
                icon: _remoteInputEnabled
                    ? LucideIcons.mousePointerClick
                    : LucideIcons.mousePointer,
                label: _remoteInputEnabled ? 'Input on' : 'Input off',
                iconSize: _floatingMenuIconSize,
                labelFontSize: _floatingMenuLabelFontSize,
                color: _remoteInputEnabled ? AppColors.ok : null,
                onPressed: () =>
                    setState(() => _remoteInputEnabled = !_remoteInputEnabled),
              ),
            ),
          Flexible(
            child: SessionMenuAction(
              icon: LucideIcons.arrowLeftRight,
              label: 'Files',
              iconSize: _floatingMenuIconSize,
              labelFontSize: _floatingMenuLabelFontSize,
              onPressed: _openFileTransferSheet,
            ),
          ),
          Flexible(
            child: SessionMenuAction(
              icon: _audioActive && !_audioMuted
                  ? LucideIcons.mic
                  : LucideIcons.micOff,
              label: _startingAudio
                  ? 'Starting'
                  : _audioActive
                  ? (_audioMuted ? 'Unmute' : 'Mute')
                  : 'Voice',
              iconSize: _floatingMenuIconSize,
              labelFontSize: _floatingMenuLabelFontSize,
              onPressed: _webrtcManager == null || _startingAudio
                  ? null
                  : _handleVoiceAction,
              onLongPress: _audioActive ? _openVoiceDialog : null,
              showSpinner: _startingAudio,
            ),
          ),
          Flexible(
            child: SessionMenuAction(
              icon: LucideIcons.phoneOff,
              label: 'Disconnect',
              iconSize: _floatingMenuIconSize,
              labelFontSize: _floatingMenuLabelFontSize,
              color: AppColors.error,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
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
