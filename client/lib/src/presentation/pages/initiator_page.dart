import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:application/src/features/file_transfer/file_transfer_widget.dart';
import 'package:application/src/features/pairing/data/connection_service.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/features/webrtc/webrtc_manager.dart';
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
  bool _signalingClosed = false;
  Timer? _heartbeatTimer;
  DateTime? _lastPongAt;
  Timer? _sessionClosedAckTimer;
  String? _sessionClosedId;
  bool _sessionClosedAcked = false;
  List<rust_share.SourceDescriptor> _shareSources = const [];
  String? _selectedSourceId;
  double _shareFps = 30;
  rust_share.BitratePreset _bitratePreset = rust_share.BitratePreset.medium;
  bool _loadingShareSources = false;
  bool _startingShare = false;
  String? _shareStatus;
  int? _mailboxExpiresAtEpochMs;
  Duration _mailboxTimeRemaining = Duration.zero;
  Duration _mailboxInitialTtl = Duration.zero;
  Timer? _mailboxCountdownTimer;
  bool _refreshingExpiredLink = false;

  final List<RTCIceCandidate> _iceCandidateQueue = [];
  bool _isSendingIce = false;

  final List<Map<String, dynamic>> _signalQueue = [];
  bool _isProcessingSignals = false;

  @override
  void initState() {
    super.initState();
    _connectionService = ConnectionService(
      signalingBaseUrl: widget.signalingBaseUrl,
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

      await _webrtcManager?.startScreenCapture(
        sourceId: _selectedSourceId!,
        fps: _shareFps.round(),
      );

      final result = rust_share.startShare(
        connectionId: connectionId,
        sourceId: _selectedSourceId!,
        config: rust_share.ShareConfig(
          fps: _shareFps.round(),
          bitratePreset: _bitratePreset,
        ),
      );

      setState(() {
        _shareStatus =
            'Share started (trackPrepared=${result.trackPrepared}, '
            'renegotiationRequired=${result.renegotiationRequired})';
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
      });
      _showSnackBar('Failed to start share');
    } finally {
      if (mounted) {
        setState(() => _startingShare = false);
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

  String _bitrateLabel(rust_share.BitratePreset preset) {
    switch (preset) {
      case rust_share.BitratePreset.low:
        return 'Low';
      case rust_share.BitratePreset.medium:
        return 'Medium';
      case rust_share.BitratePreset.high:
        return 'High';
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
    _pollTimer?.cancel();
    _mailboxSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _sessionClosedAckTimer?.cancel();
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

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
              _queueIncomingSignal(evt);
            }
          },
          onError: (_) {
            setState(() => _pollingPeer = false);
          },
        );
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
                foregroundColor: const Color(0xFF1C0F13),
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
      ShareParams(text: _connectionLink!, subject: 'P2P Connection Link'),
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
      if (type == 'webrtc_answer') {
        final data = (decoded['data'] as Map).cast<String, dynamic>();
        final answer = RTCSessionDescription(
          data['sdp'] as String,
          data['type'] as String,
        );
        unawaited(_webrtcManager?.setRemoteAnswer(answer));
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
    } catch (_) {}

    setState(() => _receivedMessage = message);
    _showSnackBar('Received: $message');
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
    _stopHeartbeat();
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
    _log.warning('Initiator: Heartbeat timeout, closing session');
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
      _log.warning('Initiator: Session closed ack not received');
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showExitConfirmation();
        if (!context.mounted) return;
        if (shouldPop) {
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
          backgroundColor: const Color(0xFF1C0F13),
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
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: _mailboxClockProgress(),
                          strokeWidth: 4,
                          backgroundColor: const Color(
                            0xFF1C0F13,
                          ).withAlpha(60),
                          color: const Color(0xFF1C0F13),
                        ),
                        Text(
                          _formatDuration(_mailboxTimeRemaining),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1C0F13),
                          ),
                        ),
                      ],
                    ),
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
                            style: TextStyle(color: Color(0xFF1C0F13)),
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
                                    : const Color(0xFF1C0F13)),
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
                  Card(
                    color: const Color(0xFFffffff),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Screen Sharing',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1C0F13),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _loadingShareSources
                                      ? null
                                      : _loadShareSources,
                                  icon: _loadingShareSources
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.monitor),
                                  label: Text(
                                    _loadingShareSources
                                        ? 'Loading Sources...'
                                        : 'Load Share Sources',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_shareSources.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedSourceId,
                              decoration: const InputDecoration(
                                labelText: 'Source',
                              ),
                              items: _shareSources
                                  .map(
                                    (source) => DropdownMenuItem<String>(
                                      value: source.sourceId,
                                      child: Text(
                                        '${source.name} '
                                        '(${_sourceKindLabel(source.kind)})',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _selectedSourceId = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            Text('FPS: ${_shareFps.round()}'),
                            Slider(
                              min: 5,
                              max: 60,
                              divisions: 11,
                              value: _shareFps,
                              label: _shareFps.round().toString(),
                              onChanged: (value) {
                                setState(() => _shareFps = value);
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<rust_share.BitratePreset>(
                              initialValue: _bitratePreset,
                              decoration: const InputDecoration(
                                labelText: 'Bitrate preset',
                              ),
                              items: rust_share.BitratePreset.values
                                  .map(
                                    (preset) =>
                                        DropdownMenuItem<
                                          rust_share.BitratePreset
                                        >(
                                          value: preset,
                                          child: Text(_bitrateLabel(preset)),
                                        ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _bitratePreset = value);
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _startingShare
                                  ? null
                                  : _startScreenShare,
                              icon: _startingShare
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.play_arrow),
                              label: Text(
                                _startingShare
                                    ? 'Starting Share...'
                                    : 'Start Share',
                              ),
                            ),
                          ],
                          if (_shareStatus != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _shareStatus!,
                              style: const TextStyle(
                                color: Color(0xFF1C0F13),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_webrtcManager != null)
                    FileTransferWidget(webrtcManager: _webrtcManager!),
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
                                color: Color(0xFF1C0F13),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _receivedMessage!,
                              style: const TextStyle(color: Color(0xFF1C0F13)),
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
