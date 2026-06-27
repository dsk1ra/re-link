import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:application/src/features/network/data/server_error.dart';
import 'package:application/src/features/pairing/data/connection_service.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/features/pairing/domain/signaling_message.dart';
import 'package:application/src/features/file_transfer/file_transfer_service.dart';
import 'package:application/src/features/pairing/domain/pairing_code.dart';
import 'package:application/src/features/session/application/serial_task_queue.dart';
import 'package:application/src/features/session/application/session_control_protocol.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/presentation/widgets/app_card.dart';
import 'package:application/src/presentation/widgets/app_ttl_timer.dart';
import 'package:application/src/presentation/widgets/dot_grid_background.dart';
import 'package:application/src/presentation/widgets/handshake_animation.dart';
import 'package:application/src/presentation/widgets/session_connection_badge.dart';
import 'package:application/src/presentation/widgets/session_file_transfer_sheet.dart';
import 'package:application/src/presentation/widgets/session_menu_overlay.dart';
import 'package:application/src/presentation/widgets/session_status_views.dart';
import 'package:application/src/presentation/widgets/session_voice_dialog.dart';
import 'package:application/src/rust/api/audio.dart' as rust_audio;
import 'package:application/src/rust/api/connection.dart' as rust_connection;
import 'package:application/src/presentation/widgets/raw_video_frame_view.dart';
import 'package:application/src/rust/api/screen_capture.dart'
    as rust_screen_capture;

/// Initiator screen - creates and shares connection link
class InitiatorPage extends StatefulWidget {
  final String signalingBaseUrl;
  final SignalingBackend backend;
  final List<Map<String, dynamic>>? iceServers;

  const InitiatorPage({
    super.key,
    required this.signalingBaseUrl,
    required this.backend,
    this.iceServers,
  });

  @override
  State<InitiatorPage> createState() => _InitiatorPageState();
}

class _InitiatorPageState extends State<InitiatorPage> {
  static final Logger _log = Logger('InitiatorPage');

  // ─── Layout / style constants ────────────────────────────────────────────
  static const double _maxPairingBodyWidth = 600;
  static const double _shareDialogWidth = 400;
  static const double _shareDropdownItemWidth = 320;
  static const double _menuHandleIconSize = 36;
  static const double _floatingMenuWidth = 340;
  static const double _floatingMenuIconSize = 20;
  static const double _floatingMenuLabelFontSize = 10;
  static const double _floatingMenuTopPadding = 10;
  static const double _menuHandleClosedTop = 0;
  static const double _menuHandleOpenTop = 108;
  static const double _menuOverlayHeight = 170;

  static const int _autoShareFps = 60;

  late ConnectionService _connectionService;
  WebRTCManager? _webrtcManager;
  FileTransferService? _fileTransferService;
  StreamSubscription<FileTransferState>? _fileTransferStateSubscription;

  RTCPeerConnectionState? _webrtcState;

  ConnectionInitResult? _initiatorResult;
  String? _connectionLink;
  String? _verificationCode;
  String? _initiatorServerMailboxId;
  bool _generatingLink = false;
  bool _waitingForPeer = false;
  bool _hasIncomingRequest = false;
  bool _peerAccepted = false;
  bool _isPeerDisconnected = false;
  StreamSubscription? _mailboxSubscription;
  bool _signalingClosed = false;
  late final SessionControlProtocol _sessionControlProtocol;
  List<rust_screen_capture.CaptureSourceDto> _shareSources = const [];
  String? _selectedSourceId;
  bool get _isPortalSource =>
      _shareSources.length == 1 && _shareSources.first.kind == 'portal';
  // Acts as the ceiling for network-adaptive quality; capture starts here
  // and steps down automatically on packet loss.
  int _bitrateSliderIndex = 3;
  static const List<int> _bitrateSteps = [500, 1000, 2000, 4000, 6000, 8000];
  bool _loadingShareSources = false;
  bool _startingShare = false;
  bool _stoppingShare = false;
  bool _isScreenSharing = false;
  bool _localPreview = false;
  bool _shareSystemAudio = true;
  bool _audioActive = false;
  bool _audioMuted = false;
  bool _remoteControlAllowed = false;
  bool _startingAudio = false;
  String? _selectedAudioSourceId;
  bool _showSessionMenu = true;
  bool _handshakeComplete = false;
  String? _shareStatus;
  bool _hasPendingIncomingFile = false;
  bool _isFileTransferSheetOpen = false;
  int? _mailboxExpiresAtEpochMs;
  Duration _mailboxTimeRemaining = Duration.zero;
  Duration _mailboxInitialTtl = Duration.zero;
  Timer? _mailboxCountdownTimer;
  bool _refreshingExpiredLink = false;

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
    _createInitiatorLink();
  }

  // ...

  Future<void> _startWebRTCHandshake() async {
    try {
      _disposeFileTransferService();
      _webrtcManager = WebRTCManager(
        connectionId: _initiatorServerMailboxId!,
        iceServers: widget.iceServers,
      );
      await _webrtcManager!.initialize();
      _attachFileTransferService(_webrtcManager!);

      _webrtcManager!.onStateChange.listen((state) {
        setState(() => _webrtcState = state);
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
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
        if (!mounted) return;
        setState(() {
          _isScreenSharing = false;
          _localPreview = false;
          _remoteControlAllowed = false;
          _shareStatus = 'Peer stopped sharing screen.';
        });
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

      final offer = await _webrtcManager!.createOffer();

      final offerMsg = SignalingMessage(
        type: 'offer',
        data: {'sdp': offer.sdp, 'type': offer.type},
      );
      final offerB64 = rust_connection.connectionEncrypt(
        keyHex: _initiatorResult!.kSig,
        plaintext: utf8.encode(offerMsg.toJsonString()),
      );
      await _connectionService.sendSignal(
        mailboxId: _initiatorServerMailboxId!,
        ciphertextB64: offerB64,
      );
    } catch (e) {
      _log.severe('Initiator WebRTC setup failed');
      _iceCandidateQueue.clear();
      _signalQueue.clear();
      await _webrtcManager?.dispose();
      _disposeFileTransferService();
      if (!mounted) return;

      final isRecoverableRendezvousError = _isRendezvousStatusError(e);
      setState(() {
        _webrtcManager = null;
        _webrtcState = null;
        _peerAccepted = false;
        _waitingForPeer = false;
        _hasIncomingRequest = false;
      });

      if (isRecoverableRendezvousError) {
        _showSnackBar('Link expired or invalid. Generating a new link...');
        if (!_generatingLink && !_refreshingExpiredLink) {
          unawaited(_createInitiatorLink(isAutoRefresh: true));
        }
      } else {
        _showSnackBar('WebRTC error: $e');
      }
    }
  }

  bool _isRendezvousStatusError(Object error) {
    final message = error.toString();
    return message.contains('404') ||
        message.contains('409') ||
        message.contains('410');
  }

  Future<void> _loadShareSources() async {
    setState(() => _loadingShareSources = true);
    try {
      final sources = _webrtcManager?.listCaptureSources() ?? const [];

      final selectedStillValid =
          _selectedSourceId != null &&
          sources.any((source) => source.id == _selectedSourceId);

      setState(() {
        _shareSources = sources;
        _selectedSourceId = selectedStillValid
            ? _selectedSourceId
            : (sources.isNotEmpty ? sources.first.id : null);
        _shareStatus = sources.isEmpty ? 'No share sources available.' : null;
      });
    } catch (e, st) {
      setState(() {
        _shareStatus = 'Failed to load share sources: $e\n\n$st';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingShareSources = false);
      }
    }
  }

  Future<void> _startScreenShare() async {
    if (_selectedSourceId == null) {
      _showSnackBar('Select a source first');
      return;
    }

    final webrtcManager = _webrtcManager;
    if (webrtcManager == null) {
      _showSnackBar('WebRTC session unavailable for share startup');
      return;
    }

    setState(() => _startingShare = true);
    try {
      if (!_isPortalSource) {
        final refreshedSources =
            _webrtcManager?.listCaptureSources() ?? const [];
        if (refreshedSources.isNotEmpty) {
          final selectedStillValid = refreshedSources.any(
            (source) => source.id == _selectedSourceId,
          );

          if (!selectedStillValid) {
            final fallbackSource = refreshedSources.first;
            if (mounted) {
              setState(() {
                _shareSources = refreshedSources;
                _selectedSourceId = fallbackSource.id;
              });
            }
            _showSnackBar(
              'Selected source is no longer available. Using: ${fallbackSource.name}',
            );
          } else if (mounted) {
            setState(() {
              _shareSources = refreshedSources;
            });
          }
        }
      }

      if (_selectedSourceId == null) {
        throw Exception('No valid screen source available');
      }

      final bitrateKbps = _bitrateSteps[_bitrateSliderIndex];

      await webrtcManager.startScreenCapture(
        sourceId: _selectedSourceId!,
        fps: _autoShareFps,
        targetBitrateKbps: bitrateKbps,
        localPreview: _localPreview,
      );

      // Desktop audio is Linux/PipeWire only for now and best-effort: a
      // failure here (e.g. no sink monitor available) shouldn't block the
      // screen share itself, just leave it silent.
      if (Platform.isLinux && _shareSystemAudio) {
        try {
          await webrtcManager.startDesktopAudioCapture();
        } catch (e) {
          _log.warning('Desktop audio capture failed to start: $e');
        }
      }

      setState(() {
        _isScreenSharing = true;
        _shareStatus =
            'Sharing screen · adaptive, up to ${bitrateKbps}kbps @ ${_autoShareFps}fps';
      });
    } catch (e, st) {
      setState(() {
        _shareStatus = 'Failed to start share: $e\n\n$st';
        _isScreenSharing = false;
        _remoteControlAllowed = false;
      });
      _showSnackBar('Failed to start share — tap error to copy');
    } finally {
      if (mounted) {
        setState(() => _startingShare = false);
      }
    }
  }

  Future<void> _stopScreenShare() async {
    if (_stoppingShare || !_isScreenSharing) return;

    setState(() => _stoppingShare = true);
    try {
      await _webrtcManager?.stopScreenCapture();
      await _webrtcManager?.sendScreenShareStopped();
      if (_remoteControlAllowed) {
        await _webrtcManager?.setRemoteControlAllowed(false);
      }
      if (Platform.isLinux && (_webrtcManager?.isDesktopAudioCaptureActive ?? false)) {
        await _webrtcManager?.stopDesktopAudioCapture();
      }

      setState(() {
        _isScreenSharing = false;
        _remoteControlAllowed = false;
        _shareStatus = 'Screen sharing stopped.';
      });
    } catch (e) {
      setState(() {
        _shareStatus = 'Failed to stop sharing: $e';
      });
      _showSnackBar('Failed to stop sharing');
    } finally {
      if (mounted) {
        setState(() => _stoppingShare = false);
      }
    }
  }

  // ─── Remote control consent ────────────────────────────────────────────────

  Future<void> _toggleRemoteControl() async {
    final manager = _webrtcManager;
    if (manager == null) return;

    final next = !_remoteControlAllowed;
    try {
      await manager.setRemoteControlAllowed(next);
      if (!mounted) return;
      setState(() => _remoteControlAllowed = next);
    } catch (e) {
      _log.warning('Remote control toggle failed: $e');
      _showSnackBar('Failed to ${next ? 'enable' : 'disable'} remote control');
    }
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

  String _sourceKindLabel(String kind) {
    switch (kind) {
      case 'display':
        return 'Display';
      case 'window':
        return 'Window';
      default:
        return kind;
    }
  }

  String _bitrateLabelForIndex(int index) {
    return '${_bitrateSteps[index]} kbps';
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
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
      keyHex: _initiatorResult!.kSig,
      plaintext: utf8.encode(iceMsg.toJsonString()),
    );
    try {
      await _connectionService.sendSignal(
        mailboxId: _initiatorServerMailboxId!,
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

  @override
  void dispose() {
    _connectionService.dispose();
    _mailboxSubscription?.cancel();
    _sessionControlProtocol.dispose();
    _iceCandidateQueue.dispose();
    _signalQueue.dispose();
    _mailboxCountdownTimer?.cancel();
    _disposeFileTransferService();
    _webrtcManager?.dispose();
    super.dispose();
  }

  Future<void> _createInitiatorLink({bool isAutoRefresh = false}) async {
    if (_refreshingExpiredLink) return;
    if (isAutoRefresh) {
      _refreshingExpiredLink = true;
    }

    final previousMailboxId = _initiatorServerMailboxId;

    setState(() => _generatingLink = true);
    try {
      _mailboxCountdownTimer?.cancel();
      _mailboxSubscription?.cancel();
      _mailboxSubscription = null;

      final initResult = await _connectionService.initializeConnectionLocally();
      final link = _connectionService.generateConnectionLink(
        initResult.rendezvousId,
        initResult.secret,
      );
      final verificationCode = formatPairingCode(initResult.sas);

      final initResp = await _connectionService.sendConnectionInit(
        rendezvousId: initResult.rendezvousId,
      );
      final serverMailboxId = initResp['mailbox_id'] as String?;
      final expiresAtEpochMs = (initResp['expires_at_epoch_ms'] as num?)
          ?.toInt();

      setState(() {
        _initiatorResult = initResult;
        _connectionLink = link;
        _verificationCode = verificationCode;
        _generatingLink = false;
        _waitingForPeer = serverMailboxId != null;
        _peerAccepted = false;
        _hasIncomingRequest = false;
        _mailboxExpiresAtEpochMs = expiresAtEpochMs;
        _mailboxTimeRemaining = _remainingFromEpochMs(expiresAtEpochMs);
        _mailboxInitialTtl = _remainingFromEpochMs(expiresAtEpochMs);
      });

      if (serverMailboxId != null) {
        _initiatorServerMailboxId = serverMailboxId;
        _startListeningForPeer(serverMailboxId);
      }

      _startMailboxCountdown();

      if (previousMailboxId != null && previousMailboxId != serverMailboxId) {
        try {
          await _connectionService.closeConnection(
            mailboxId: previousMailboxId,
          );
        } catch (_) {}
      }
    } catch (e) {
      final classified = ServerError.classify(e);
      setState(() {
        _generatingLink = false;
        _verificationCode = null;
      });
      _showSnackBar(classified.userMessage);
    } finally {
      _refreshingExpiredLink = false;
    }
  }

  Duration _remainingFromEpochMs(int? expiresAtEpochMs) {
    if (expiresAtEpochMs == null) return Duration.zero;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtEpochMs);
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return Duration.zero;
    return remaining;
  }

  void _startMailboxCountdown() {
    _mailboxCountdownTimer?.cancel();
    _tickMailboxCountdown();
    _mailboxCountdownTimer = Timer.periodic(const Duration(milliseconds: 200), (
      _,
    ) {
      _tickMailboxCountdown();
    });
  }

  void _tickMailboxCountdown() {
    if (_peerAccepted || _signalingClosed) {
      _mailboxCountdownTimer?.cancel();
      return;
    }

    final remaining = _remainingFromEpochMs(_mailboxExpiresAtEpochMs);
    if (!mounted) return;

    setState(() {
      _mailboxTimeRemaining = remaining;
    });

    if (remaining == Duration.zero &&
        !_generatingLink &&
        !_refreshingExpiredLink) {
      unawaited(_createInitiatorLink(isAutoRefresh: true));
    }
  }

  double _mailboxClockProgress() {
    final totalMs = _mailboxInitialTtl.inMilliseconds;
    if (totalMs <= 0) return 0;
    final remainingMs = _mailboxTimeRemaining.inMilliseconds;
    return (remainingMs / totalMs).clamp(0.0, 1.0);
  }

  void _startListeningForPeer(String mailboxId) {
    _mailboxSubscription?.cancel();
    setState(() => _waitingForPeer = true);

    _mailboxSubscription = _connectionService
        .subscribeMailbox(mailboxId: mailboxId)
        .listen(
          (evt) {
            if (!_peerAccepted && !_hasIncomingRequest) {
              setState(() {
                _waitingForPeer = false;
                _hasIncomingRequest = true;
              });
              _showIncomingDialog();
            } else if (_peerAccepted) {
              _signalQueue.enqueue(evt);
            }
          },
          onError: (_) {
            setState(() => _waitingForPeer = false);
          },
        );
  }

  void _showIncomingDialog() {
    if (!_hasIncomingRequest) return;
    final verificationCode = _verificationCode;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var codeVerified = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('INCOMING CONNECTION', style: AppTypography.eyebrow),
                  const SizedBox(height: AppSpacing.sm),
                  Text('A peer wants to connect', style: AppTypography.h2),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (verificationCode != null) ...[
                    Text('VERIFY WITH PEER', style: AppTypography.eyebrow),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.borderStrong),
                      ),
                      child: Text(
                        verificationCode,
                        textAlign: TextAlign.center,
                        style: AppTypography.displayData.copyWith(
                          fontSize: 28,
                          letterSpacing: 28 * 0.08,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Read this code aloud to your peer. '
                      'Only accept if they confirm it matches.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    GestureDetector(
                      onTap: () =>
                          setDialogState(() => codeVerified = !codeVerified),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: codeVerified,
                              onChanged: (v) =>
                                  setDialogState(() => codeVerified = v!),
                              activeColor: AppColors.action,
                              checkColor: AppColors.onAction,
                              side: const BorderSide(
                                color: AppColors.borderStrong,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'My peer confirmed the code matches',
                              style: AppTypography.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    setState(() => _hasIncomingRequest = false);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  child: const Text('REJECT'),
                ),
                AppButton(
                  onPressed: codeVerified
                      ? () async {
                          Navigator.of(ctx).pop();

                          if (_remainingFromEpochMs(_mailboxExpiresAtEpochMs) ==
                              Duration.zero) {
                            setState(() {
                              _hasIncomingRequest = false;
                              _peerAccepted = false;
                            });
                            _showSnackBar(
                              'Link expired. Generating a new link...',
                            );
                            if (!_generatingLink && !_refreshingExpiredLink) {
                              unawaited(
                                _createInitiatorLink(isAutoRefresh: true),
                              );
                            }
                            return;
                          }

                          setState(() {
                            _peerAccepted = true;
                            _hasIncomingRequest = false;
                            _handshakeComplete = false;
                          });
                          await _startWebRTCHandshake();
                        }
                      : null,
                  label: 'Accept',
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleIncomingSignal(Map<String, dynamic> msg) async {
    final payloadB64 = msg['ciphertext_b64'] as String?;
    if (payloadB64 == null || payloadB64.isEmpty) return;
    if (_signalingClosed) return;

    try {
      final decryptedBytes = rust_connection.connectionDecrypt(
        keyHex: _initiatorResult!.kSig,
        ciphertextB64: payloadB64,
      );
      final decoded = utf8.decode(decryptedBytes);
      final signalingMsg = SignalingMessage.fromJsonString(decoded);

      if (signalingMsg.type == 'answer') {
        final answer = RTCSessionDescription(
          signalingMsg.data['sdp'] as String,
          signalingMsg.data['type'] as String,
        );
        await _webrtcManager!.setRemoteAnswer(answer);
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
      _log.warning('Initiator signal handling failed');
    }
  }

  Future<void> _copyLink() async {
    if (_connectionLink == null) return;
    await Clipboard.setData(ClipboardData(text: _connectionLink!));
    _showSnackBar('Link copied');
  }

  Future<void> _shareLink() async {
    if (_connectionLink == null) return;
    await SharePlus.instance.share(
      ShareParams(text: _connectionLink!, subject: 'Connection Link'),
    );
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
    final mailboxId = _initiatorServerMailboxId;
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
    _showSnackBar('Peer has disconnected.');
    _sessionControlProtocol.stopHeartbeat();
    await _webrtcManager?.dispose();
    _disposeFileTransferService();
    setState(() {
      _webrtcManager = null;
      _webrtcState = null;
      _isPeerDisconnected = true;
      _isScreenSharing = false;
      _remoteControlAllowed = false;
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
    if (_initiatorResult == null || _initiatorServerMailboxId == null) return;
    try {
      final msg = SignalingMessage(type: 'disconnect', data: {});
      final encryptedB64 = rust_connection.connectionEncrypt(
        keyHex: _initiatorResult!.kSig,
        plaintext: utf8.encode(msg.toJsonString()),
      );
      await _connectionService.sendSignal(
        mailboxId: _initiatorServerMailboxId!,
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
                title: const Text('CREATE CONNECTION'),
                actions: [
                  if (_peerAccepted) ...[
                    _buildConnectionBadge(),
                    const SizedBox(width: AppSpacing.md),
                  ],
                ],
              ),
        body: _peerAccepted
            ? _buildConnectedLayout()
            : DotGridBackground(child: _buildPairingBody()),
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

  // ─── Pre-acceptance pairing body ──────────────────────────────────────────

  Widget _buildPairingBody() {
    final verificationCode = formatPairingCode(_initiatorResult?.sas);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxPairingBodyWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_generatingLink)
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                )
              else if (_connectionLink != null && !_peerAccepted) ...[
                Text('INVITE', style: AppTypography.eyebrow),
                const SizedBox(height: AppSpacing.sm),
                Text('Share this with your peer', style: AppTypography.h1),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  eyebrow: 'Connection link',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText(
                        _connectionLink!,
                        style: AppTypography.data.copyWith(
                          color: AppColors.info,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTtlTimer(
                        remaining: _mailboxTimeRemaining,
                        progress: _mailboxClockProgress(),
                      ),
                    ],
                  ),
                ),
                if (verificationCode != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    eyebrow: 'Verification code',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          verificationCode,
                          style: AppTypography.displayData.copyWith(
                            fontSize: 28,
                            letterSpacing: 28 * 0.08,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Ask your peer to read back this code before you '
                          'accept the session.',
                          style: AppTypography.body.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        onPressed: _copyLink,
                        icon: LucideIcons.copy,
                        label: 'Copy link',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AppButton(
                        onPressed: _shareLink,
                        icon: LucideIcons.share2,
                        label: 'Share',
                        variant: AppButtonVariant.outline,
                      ),
                    ),
                  ],
                ),
                if (_waitingForPeer) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.warn,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                      Text(
                        'WAITING FOR PEER',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.warn,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                _buildServerVisibilityPanel(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Server visibility panel ──────────────────────────────────────────────

  Widget _buildServerVisibilityPanel() {
    Widget row(String label, String value, {bool visible = true}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textFaint,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AppTypography.caption.copyWith(
                  color: visible ? AppColors.info : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WHAT THE SERVER SEES', style: AppTypography.eyebrow),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          row('MAILBOX ID', _initiatorServerMailboxId ?? '—'),
          row('PAYLOADS', 'ciphertext only (AEAD)'),
          row('EXPIRY', 'enforced by TTL'),
          const SizedBox(height: AppSpacing.sm),
          Text('NEVER LEAVES THE PEERS', style: AppTypography.eyebrow),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          row('SESSION KEYS', 'k_sig · k_mac', visible: false),
          row('SAS CODE', 'verified out-of-band', visible: false),
          row('CONTENT', 'screen, files, control', visible: false),
        ],
      ),
    );
  }

  // ─── Post-acceptance connected layout ─────────────────────────────────────

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
        child: HandshakeAnimation(
          connected: isConnected,
          onFinished: () {
            if (!mounted) return;
            setState(() => _handshakeComplete = true);
          },
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: _buildSessionMainArea()),
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

  // ─── Left content area (host idle view) ───────────────────────────────────

  Widget _buildSessionMainArea() {
    if (_isScreenSharing && _localPreview && _webrtcManager != null) {
      return Container(
        color: AppColors.background,
        child: RawVideoFrameView(
          frameStream: _webrtcManager!.onVideoFrame,
          fit: BoxFit.contain,
        ),
      );
    }

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
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
                  'SESSION ACTIVE · HOST',
                  style: AppTypography.eyebrow.copyWith(color: AppColors.ok),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('You are hosting this session', style: AppTypography.h2),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Use the menu to share your screen or transfer files.',
              style: AppTypography.body.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingMenu() {
    return SessionMenuCard(
      width: _floatingMenuWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Flexible(
                child: SessionMenuAction(
                  icon: LucideIcons.monitor,
                  label: _loadingShareSources
                      ? 'Loading'
                      : _startingShare
                      ? 'Starting'
                      : 'Screen',
                  iconSize: _floatingMenuIconSize,
                  labelFontSize: _floatingMenuLabelFontSize,
                  onPressed:
                      _loadingShareSources || _startingShare || _stoppingShare
                      ? null
                      : _openShareSourceDialog,
                  showSpinner: _loadingShareSources || _startingShare,
                ),
              ),
              Flexible(
                child: SessionMenuAction(
                  icon: LucideIcons.arrowLeftRight,
                  label: 'Files',
                  iconSize: _floatingMenuIconSize,
                  labelFontSize: _floatingMenuLabelFontSize,
                  onPressed: _webrtcManager == null
                      ? null
                      : _openFileTransferSheet,
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
              if (_isScreenSharing)
                Flexible(
                  child: SessionMenuAction(
                    icon: _remoteControlAllowed
                        ? LucideIcons.mousePointerClick
                        : LucideIcons.mousePointer,
                    label: _remoteControlAllowed ? 'Input on' : 'Input off',
                    iconSize: _floatingMenuIconSize,
                    labelFontSize: _floatingMenuLabelFontSize,
                    color: _remoteControlAllowed ? AppColors.ok : null,
                    onPressed: _toggleRemoteControl,
                  ),
                ),
              if (_isScreenSharing)
                Flexible(
                  child: SessionMenuAction(
                    icon: LucideIcons.monitorOff,
                    label: _stoppingShare ? 'Stopping' : 'Stop',
                    iconSize: _floatingMenuIconSize,
                    labelFontSize: _floatingMenuLabelFontSize,
                    color: AppColors.error,
                    onPressed: _stoppingShare ? null : _stopScreenShare,
                    showSpinner: _stoppingShare,
                  ),
                ),
            ],
          ),
          if (_shareStatus != null) ...[
            const SizedBox(height: AppSpacing.sm),
            if (_shareStatus!.startsWith('Failed'))
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _shareStatus!));
                  _showSnackBar('Error copied to clipboard');
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _shareStatus!,
                        style: AppTypography.caption
                            .copyWith(color: AppColors.error),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      LucideIcons.copy,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              )
            else
              Text(
                _shareStatus!,
                style:
                    AppTypography.caption.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
          ],
        ],
      ),
    );
  }

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

  // ─── Share source dialog ──────────────────────────────────────────────────

  Future<void> _openShareSourceDialog() async {
    await _loadShareSources();
    if (!mounted) return;

    String? dialogSourceId = _selectedSourceId;
    int dialogBitrateIndex = _bitrateSliderIndex;
    bool dialogLocalPreview = _localPreview;
    bool dialogShareAudio = _shareSystemAudio;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SCREEN SHARE', style: AppTypography.eyebrow),
              const SizedBox(height: AppSpacing.sm),
              Text('Share screen', style: AppTypography.h2),
            ],
          ),
          content: SizedBox(
            width: _shareDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_shareSources.isEmpty)
                  Text(
                    'No sources available.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textMuted,
                    ),
                  )
                else if (_isPortalSource)
                  Text(
                    'Your system will ask which screen to share.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textMuted,
                    ),
                  )
                else ...[
                  Text('SOURCE', style: AppTypography.eyebrow),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: dialogSourceId,
                    dropdownColor: AppColors.surface2,
                    style: AppTypography.label,
                    items: _shareSources
                        .map(
                          (source) => DropdownMenuItem<String>(
                            value: source.id,
                            child: SizedBox(
                              width: _shareDropdownItemWidth,
                              child: Text(
                                '${source.name} (${_sourceKindLabel(source.kind)})',
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.label,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setDialogState(() => dialogSourceId = val),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Theme(
                    data: Theme.of(
                      ctx,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: Text(
                        'ADVANCED OPTIONS',
                        style: AppTypography.eyebrow,
                      ),
                      tilePadding: EdgeInsets.zero,
                      iconColor: AppColors.textMuted,
                      collapsedIconColor: AppColors.textMuted,
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'MAX BITRATE: ${_bitrateLabelForIndex(dialogBitrateIndex)}',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                        Slider(
                          min: 0,
                          max: 3,
                          divisions: 3,
                          value: dialogBitrateIndex.toDouble(),
                          label: _bitrateLabelForIndex(dialogBitrateIndex),
                          activeColor: AppColors.action,
                          onChanged: (val) => setDialogState(
                            () => dialogBitrateIndex = val.round(),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        GestureDetector(
                          onTap: () => setDialogState(
                            () => dialogLocalPreview = !dialogLocalPreview,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: dialogLocalPreview,
                                  onChanged: (v) => setDialogState(
                                    () => dialogLocalPreview = v!,
                                  ),
                                  activeColor: AppColors.action,
                                  checkColor: AppColors.onAction,
                                  side: const BorderSide(
                                    color: AppColors.borderStrong,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Show local preview (downscaled)',
                                style: AppTypography.label,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  ),
                ],
                if (Platform.isLinux && _shareSources.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  GestureDetector(
                    onTap: () => setDialogState(
                      () => dialogShareAudio = !dialogShareAudio,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: dialogShareAudio,
                            onChanged: (v) => setDialogState(
                              () => dialogShareAudio = v!,
                            ),
                            activeColor: AppColors.action,
                            checkColor: AppColors.onAction,
                            side: const BorderSide(
                              color: AppColors.borderStrong,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Share system audio',
                          style: AppTypography.label,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
              child: const Text('CANCEL'),
            ),
            AppButton(
              onPressed: dialogSourceId == null
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              icon: LucideIcons.play,
              label: 'Start sharing',
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        _selectedSourceId = dialogSourceId;
        _bitrateSliderIndex = dialogBitrateIndex;
        _localPreview = dialogLocalPreview;
        _shareSystemAudio = dialogShareAudio;
      });
      await _startScreenShare();
    }
  }
}
