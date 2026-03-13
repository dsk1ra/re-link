import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:application/src/features/pairing/data/connection_service.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/features/session/application/serial_task_queue.dart';
import 'package:application/src/features/session/application/session_control_protocol.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_card.dart';
import 'package:application/src/presentation/widgets/app_ttl_timer.dart';
import 'package:application/src/presentation/widgets/session_connection_badge.dart';
import 'package:application/src/presentation/widgets/session_file_transfer_sheet.dart';
import 'package:application/src/presentation/widgets/session_menu_overlay.dart';
import 'package:application/src/presentation/widgets/session_status_views.dart';
import 'package:application/src/rust/api/connection.dart' as rust_connection;
import 'package:application/src/rust/api/share.dart' as rust_share;
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
  static final Logger _log = Logger('InitiatorPage');

  // ─── Layout / style constants ────────────────────────────────────────────
  static const double _sectionTitleFontSize = 18;
  static const double _sessionTitleFontSize = 22;
  static const double _linkFontSize = 12;
  static const double _dialogDetailFontSize = 12;
  static const double _dropdownItemFontSize = 14;
  static const double _advancedOptionsFontSize = 13;
  static const double _maxPairingBodyWidth = 600;
  static const double _sessionIconSize = 88;
  static const double _shareDialogWidth = 400;
  static const double _shareDropdownItemWidth = 320;
  static const double _menuHandleIconSize = 45;
  static const double _floatingMenuWidth = 280;
  static const double _floatingMenuIconSize = 22;
  static const double _floatingMenuLabelFontSize = 11;
  static const double _floatingMenuTopPadding = 10;
  static const double _floatingMenuCornerRadius = 14;
  static const double _floatingMenuStatusFontSize = 12;
  static const double _menuHandleClosedTop = 0;
  static const double _menuHandleOpenTop = 108;
  static const double _menuOverlayHeight = 170;
  static const double _dragHandleWidth = 40;
  static const double _dragHandleHeight = 4;
  static const double _dragHandleBorderRadius = 2;
  static const double _sheetHeaderIconSize = 18;
  static const double _sheetHeaderIconGap = AppSpacing.sm;
  static const EdgeInsets _shareDropdownContentPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );
  static const double _dialogSpacing = AppSpacing.base;
  static const int _autoShareFps = 30;

  late ConnectionService _connectionService;
  WebRTCManager? _webrtcManager;

  RTCPeerConnectionState? _webrtcState;

  ConnectionInitResult? _initiatorResult;
  String? _connectionLink;
  String? _initiatorServerMailboxId;
  bool _generatingLink = false;
  bool _pollingPeer = false;

  String? _incomingRequestFrom;
  bool _peerAccepted = false;
  bool _isPeerDisconnected = false;
  StreamSubscription? _mailboxSubscription;
  bool _signalingClosed = false;
  late final SessionControlProtocol _sessionControlProtocol;
  List<rust_share.SourceDescriptor> _shareSources = const [];
  String? _selectedSourceId;
  // 0 = Auto (adaptive), 1–5 = fixed kbps from _bitrateSteps
  int _bitrateSliderIndex = 0;
  static const List<int?> _bitrateSteps = [null, 500, 1000, 2000, 4000, 8000];
  StreamSubscription? _qualitySubscription;
  bool _loadingShareSources = false;
  bool _startingShare = false;
  bool _stoppingShare = false;
  bool _isScreenSharing = false;
  bool _showSessionMenu = false;
  String? _shareStatus;
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
        setState(() {
          _isScreenSharing = false;
          _shareStatus = 'Peer stopped sharing screen.';
        });
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
    _createInitiatorLink();
  }

  // ...

  Future<void> _startWebRTCHandshake() async {
    try {
      _log.info('Initiator: Starting WebRTC Handshake...');
      _webrtcManager = WebRTCManager();
      _log.info('Initiator: Initializing WebRTCManager...');
      await _webrtcManager!.initialize();
      _log.info('Initiator: WebRTCManager initialized.');

      _webrtcManager!.onStateChange.listen((state) {
        _log.info('Initiator: State changed to $state');
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

      _log.info('Initiator: Creating Offer...');
      final offer = await _webrtcManager!.createOffer();
      _log.info('Initiator: Created Offer');

      final offerMsg = SignalingMessage(
        type: 'offer',
        data: {'sdp': offer.sdp, 'type': offer.type},
      );
      final offerB64 = rust_connection.connectionEncrypt(
        keyHex: _initiatorResult!.kSig,
        plaintext: utf8.encode(offerMsg.toJsonString()),
      );
      _log.info('Initiator: Sending Offer...');
      await _connectionService.sendSignal(
        mailboxId: _initiatorServerMailboxId!,
        ciphertextB64: offerB64,
      );
    } catch (e) {
      _log.severe('Initiator: WebRTC Error', e);
      _showSnackBar('WebRTC error: $e');
    }
  }

  Future<void> _loadShareSources() async {
    setState(() => _loadingShareSources = true);
    try {
      rust_share.init();
      var sources = await _listDesktopShareSources();
      if (sources.isEmpty) {
        sources = rust_share.listShareSources();
      }

      final selectedStillValid =
          _selectedSourceId != null &&
          sources.any((source) => source.sourceId == _selectedSourceId);

      setState(() {
        _shareSources = sources;
        _selectedSourceId = selectedStillValid
            ? _selectedSourceId
            : (sources.isNotEmpty ? sources.first.sourceId : null);
        _shareStatus = sources.isEmpty ? 'No share sources available.' : null;
      });
    } catch (e) {
      setState(() {
        _shareStatus = 'Failed to load share sources: $e';
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

    final connectionId = _initiatorServerMailboxId;
    if (connectionId == null || connectionId.isEmpty) {
      _showSnackBar('Connection ID unavailable for share startup');
      return;
    }

    setState(() => _startingShare = true);
    try {
      final refreshedSources = await _listDesktopShareSources();
      if (refreshedSources.isNotEmpty) {
        final selectedStillValid = refreshedSources.any(
          (source) => source.sourceId == _selectedSourceId,
        );

        if (!selectedStillValid) {
          final fallbackSource = refreshedSources.first;
          if (mounted) {
            setState(() {
              _shareSources = refreshedSources;
              _selectedSourceId = fallbackSource.sourceId;
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

      if (_selectedSourceId == null) {
        throw Exception('No valid screen source available');
      }

      final bitrateKbps = _bitrateSteps[_bitrateSliderIndex];
      await _webrtcManager?.startScreenCapture(
        sourceId: _selectedSourceId!,
        fps: _autoShareFps,
        bitrateKbps: bitrateKbps,
      );

      // Subscribe to adaptive quality tier changes
      _qualitySubscription?.cancel();
      _qualitySubscription = _webrtcManager?.onQualityChange.listen((msg) {
        if (!mounted) return;
        final parsed = _parseAdaptiveQualityStatus(msg);
        if (parsed == null) return;
        setState(() {
          _shareStatus = _buildShareStatus(
            resolution: parsed.$1,
            fps: parsed.$2,
          );
        });
      });

      rust_share.startShare(
        connectionId: connectionId,
        sourceId: _selectedSourceId!,
        config: rust_share.ShareConfig(
          fps: _autoShareFps,
          bitratePreset: rust_share.BitratePreset.high,
        ),
      );

      setState(() {
        _isScreenSharing = true;
        _shareStatus = _buildShareStatus(
          resolution: '1080p',
          fps: _autoShareFps,
        );
      });

      final offer = await _webrtcManager!.createRenegotiationOffer();
      final msg = jsonEncode({
        'type': 'webrtc_offer',
        'data': {'sdp': offer.sdp, 'type': offer.type},
      });
      await _webrtcManager?.sendControlMessage(msg);
    } catch (e) {
      setState(() {
        _shareStatus = 'Failed to start share: $e';
        _isScreenSharing = false;
      });
      _showSnackBar('Failed to start share');
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

      final msg = jsonEncode({'type': 'screen_share_stopped'});
      await _webrtcManager?.sendControlMessage(msg);

      final offer = await _webrtcManager!.createRenegotiationOffer();
      final renegotiateMsg = jsonEncode({
        'type': 'webrtc_offer',
        'data': {'sdp': offer.sdp, 'type': offer.type},
      });
      await _webrtcManager?.sendControlMessage(renegotiateMsg);

      setState(() {
        _isScreenSharing = false;
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

  Future<List<rust_share.SourceDescriptor>> _listDesktopShareSources() async {
    try {
      final sources = await desktopCapturer.getSources(
        types: <SourceType>[SourceType.Screen, SourceType.Window],
      );

      return sources
          .map(
            (source) => rust_share.SourceDescriptor(
              sourceId: source.id,
              kind: source.id.startsWith('window:')
                  ? rust_share.SourceKind.window
                  : rust_share.SourceKind.display,
              name: source.name.isNotEmpty ? source.name : source.id,
              width: null,
              height: null,
            ),
          )
          .toList();
    } catch (e) {
      _log.warning('Failed to query desktop sources from flutter_webrtc: $e');
      return const [];
    }
  }

  String _sourceKindLabel(rust_share.SourceKind kind) {
    switch (kind) {
      case rust_share.SourceKind.display:
        return 'Display';
      case rust_share.SourceKind.window:
        return 'Window';
    }
  }

  String _bitrateLabelForIndex(int index) {
    final kbps = _bitrateSteps[index];
    return kbps == null ? 'Auto' : '$kbps kbps';
  }

  String _buildShareStatus({required String resolution, required int fps}) {
    return 'Sharing @ $resolution, ${fps}fps';
  }

  (String, int)? _parseAdaptiveQualityStatus(String status) {
    final match = RegExp(r'(\d{3,4}p).*?(\d{1,2})fps').firstMatch(status);
    if (match == null) return null;
    final resolution = match.group(1);
    final fps = int.tryParse(match.group(2) ?? '');
    if (resolution == null || fps == null) return null;
    return (resolution, fps);
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
    await _connectionService.sendSignal(
      mailboxId: _initiatorServerMailboxId!,
      ciphertextB64: iceB64,
    );
  }

  @override
  void dispose() {
    _connectionService.dispose();
    _mailboxSubscription?.cancel();
    _qualitySubscription?.cancel();
    _sessionControlProtocol.dispose();
    _iceCandidateQueue.dispose();
    _signalQueue.dispose();
    _mailboxCountdownTimer?.cancel();
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

      final initResp = await _connectionService.sendConnectionInit(
        clientId: widget.backend.clientId ?? '',
        sessionToken: widget.backend.sessionToken ?? '',
        rendezvousId: initResult.rendezvousId,
      );
      final serverMailboxId = initResp['mailbox_id'] as String?;
      final expiresAtEpochMs = (initResp['expires_at_epoch_ms'] as num?)
          ?.toInt();

      if (serverMailboxId != null) {
        _initiatorServerMailboxId = serverMailboxId;
        _startListeningForPeer(serverMailboxId);
      }

      setState(() {
        _initiatorResult = initResult;
        _connectionLink = link;
        _generatingLink = false;
        _pollingPeer = serverMailboxId != null;
        _peerAccepted = false;
        _incomingRequestFrom = null;
        _mailboxExpiresAtEpochMs = expiresAtEpochMs;
        _mailboxTimeRemaining = _remainingFromEpochMs(expiresAtEpochMs);
        _mailboxInitialTtl = _remainingFromEpochMs(expiresAtEpochMs);
      });

      _startMailboxCountdown();

      if (previousMailboxId != null && previousMailboxId != serverMailboxId) {
        try {
          await _connectionService.closeConnection(
            mailboxId: previousMailboxId,
          );
        } catch (_) {}
      }
    } catch (e) {
      setState(() => _generatingLink = false);
      _showSnackBar('Error: $e');
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
    setState(() => _pollingPeer = true);

    _mailboxSubscription = _connectionService
        .subscribeMailbox(mailboxId: mailboxId)
        .listen(
          (evt) {
            if (!_peerAccepted && _incomingRequestFrom == null) {
              setState(() {
                _pollingPeer = false;
                _incomingRequestFrom = evt['from_mailbox_id'] as String?;
              });
              _showIncomingDialog();
            } else if (_peerAccepted) {
              _signalQueue.enqueue(evt);
            }
          },
          onError: (_) {
            setState(() => _pollingPeer = false);
          },
        );
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
              SizedBox(height: _dialogSpacing),
              const Text('A peer wants to connect'),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'From: $_incomingRequestFrom',
                style: AppTypography.body(
                  size: _dialogDetailFontSize,
                  color: AppColors.textMuted,
                ),
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
                foregroundColor: AppColors.textPrimary,
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
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
              child: const Text('Accept'),
            ),
          ],
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
      _log.info('Initiator: Received Signal: $decoded');
      final signalingMsg = SignalingMessage.fromJsonString(decoded);

      if (signalingMsg.type == 'answer') {
        _log.info('Initiator: Processing Answer...');
        final answer = RTCSessionDescription(
          signalingMsg.data['sdp'] as String,
          signalingMsg.data['type'] as String,
        );
        await _webrtcManager!.setRemoteAnswer(answer);
      } else if (signalingMsg.type == 'ice') {
        _log.info('Initiator: Processing ICE Candidate...');
        final candidate = RTCIceCandidate(
          signalingMsg.data['candidate'] as String,
          signalingMsg.data['sdpMid'] as String,
          signalingMsg.data['sdpMLineIndex'] as int,
        );
        await _webrtcManager!.addIceCandidate(candidate);
      } else if (signalingMsg.type == 'disconnect') {
        _log.info('Initiator: Peer disconnected');
        _showSnackBar('Peer has disconnected.');
        await _webrtcManager?.dispose();
        setState(() {
          _webrtcManager = null;
          _webrtcState = null;
          _isPeerDisconnected = true;
        });
      }
    } catch (e) {
      _log.warning('Initiator: Error handling signal: $e');
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

  void _handleControlMessage(String message) {
    unawaited(_sessionControlProtocol.handleMessage(message));
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
    } catch (e) {
      _log.warning('Failed to close signaling mailbox: $e');
    }
  }

  Future<void> _handlePeerSessionClosed() async {
    _log.info('Initiator: Peer session closed over WebRTC');
    _showSnackBar('Peer has disconnected.');
    _sessionControlProtocol.stopHeartbeat();
    await _webrtcManager?.dispose();
    setState(() {
      _webrtcManager = null;
      _webrtcState = null;
      _isPeerDisconnected = true;
      _isScreenSharing = false;
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
                  'Create Connection',
                  style: AppTypography.title(
                    size: AppUiMetrics.appBarTitleFontSize,
                  ),
                ),
                backgroundColor: AppColors.surface,
                elevation: 0,
                iconTheme: const IconThemeData(color: AppColors.textPrimary),
                actions: [
                  if (_peerAccepted) ...[
                    _buildConnectionBadge(),
                    const SizedBox(width: AppSpacing.md),
                  ],
                ],
              ),
        body: _peerAccepted ? _buildConnectedLayout() : _buildPairingBody(),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxPairingBodyWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_generatingLink)
                const Center(child: CircularProgressIndicator())
              else if (_connectionLink != null && !_peerAccepted) ...[
                Text(
                  'Share this with your peer',
                  style: AppTypography.title(size: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: AppTtlTimer(
                    remaining: _mailboxTimeRemaining,
                    progress: _mailboxClockProgress(),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Connection Link',
                        style: AppTypography.body(weight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SelectableText(
                        _connectionLink!,
                        style: AppTypography.mono(size: _linkFontSize),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _copyLink,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy Link'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _shareLink,
                        icon: const Icon(Icons.share),
                        label: const Text('Share'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_pollingPeer) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppSpacing.base),
                        Text(
                          'Waiting for peer...',
                          style: AppTypography.body(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
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

    if (_webrtcState !=
        RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      return const SessionConnectingView(message: 'Establishing connection…');
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
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.computer,
              size: _sessionIconSize,
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Session Active',
              style: AppTypography.title(size: _sessionTitleFontSize),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'You are hosting this session.\nUse the menu to share your screen or transfer files.',
              style: AppTypography.body(color: AppColors.textMuted),
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
      cornerRadius: _floatingMenuCornerRadius,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              SessionMenuAction(
                icon: Icons.monitor,
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
              SessionMenuAction(
                icon: Icons.swap_horiz,
                label: 'Files',
                iconSize: _floatingMenuIconSize,
                labelFontSize: _floatingMenuLabelFontSize,
                onPressed: _webrtcManager == null
                    ? null
                    : _openFileTransferSheet,
              ),
              SessionMenuAction(
                icon: Icons.call_end,
                label: 'Disconnect',
                iconSize: _floatingMenuIconSize,
                labelFontSize: _floatingMenuLabelFontSize,
                color: AppColors.error,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              if (_isScreenSharing)
                SessionMenuAction(
                  icon: Icons.stop_screen_share,
                  label: _stoppingShare ? 'Stopping' : 'Stop',
                  iconSize: _floatingMenuIconSize,
                  labelFontSize: _floatingMenuLabelFontSize,
                  color: AppColors.error,
                  onPressed: _stoppingShare ? null : _stopScreenShare,
                  showSpinner: _stoppingShare,
                ),
            ],
          ),
          if (_shareStatus != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _shareStatus!,
              style: AppTypography.body(
                size: _floatingMenuStatusFontSize,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  void _openFileTransferSheet() {
    if (_webrtcManager == null) return;
    showSessionFileTransferSheet(
      context: context,
      webrtcManager: _webrtcManager!,
    );
  }

  // ─── Share source dialog ──────────────────────────────────────────────────

  Future<void> _openShareSourceDialog() async {
    await _loadShareSources();
    if (!mounted) return;

    // Local mutable dialog state
    String? dialogSourceId = _selectedSourceId;
    int dialogBitrateIndex = _bitrateSliderIndex;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Share Screen',
            style: AppTypography.title(size: _sectionTitleFontSize),
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
                    style: AppTypography.body(color: AppColors.textMuted),
                  )
                else ...[
                  Text(
                    'Source',
                    style: AppTypography.body(
                      color: AppColors.textMuted,
                      size: 12,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: dialogSourceId,
                    dropdownColor: AppColors.surface,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                      contentPadding: _shareDropdownContentPadding,
                    ),
                    items: _shareSources
                        .map(
                          (source) => DropdownMenuItem<String>(
                            value: source.sourceId,
                            child: SizedBox(
                              width: _shareDropdownItemWidth,
                              child: Text(
                                '${source.name} (${_sourceKindLabel(source.kind)})',
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.body(
                                  color: AppColors.textPrimary,
                                  size: _dropdownItemFontSize,
                                ),
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
                        'Advanced Options',
                        style: AppTypography.body(
                          size: _advancedOptionsFontSize,
                          weight: FontWeight.w600,
                        ),
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
                              'Bitrate: ${_bitrateLabelForIndex(dialogBitrateIndex)}',
                              style: AppTypography.body(),
                            ),
                          ],
                        ),
                        Slider(
                          min: 0,
                          max: 5,
                          divisions: 5,
                          value: dialogBitrateIndex.toDouble(),
                          label: _bitrateLabelForIndex(dialogBitrateIndex),
                          activeColor: AppColors.primary,
                          onChanged: (val) => setDialogState(
                            () => dialogBitrateIndex = val.round(),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
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
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: dialogSourceId == null
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Sharing'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        _selectedSourceId = dialogSourceId;
        _bitrateSliderIndex = dialogBitrateIndex;
      });
      await _startScreenShare();
    }
  }
}
