import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

/// Manages WebRTC peer connection with minimal signaling
class WebRTCManager {
  static final Logger _log = Logger('WebRTCManager');

  // ─── Magic number constants ────────────────────────────────────────────
  static const int _KBPS_TO_BPS_MULTIPLIER = 1000;
  static const int _DEFAULT_BITRATE_KBPS = 2000;
  static const int _DEFAULT_FPS = 30;
  static const int _MIN_FRAMERATE = 1;
  static const int _MAX_WIDTH = 1920;
  static const int _MAX_HEIGHT = 1080;
  static const int _ADAPTIVE_QUALITY_POLL_INTERVAL_SECONDS = 5;
  static const int _QUALITY_TIER_MAX = 3;
  static const double _QUALITY_BAD_FRACTION_LOST_THRESHOLD = 0.05;
  static const double _QUALITY_GOOD_FRACTION_LOST_THRESHOLD = 0.01;
  static const double _QUALITY_BAD_RTT_THRESHOLD = 0.5;
  static const double _QUALITY_GOOD_RTT_THRESHOLD = 0.2;
  static const int _CONSECUTIVE_BAD_POLLS_FOR_DOWNGRADE = 2;
  static const int _CONSECUTIVE_GOOD_POLLS_FOR_UPGRADE = 4;
  static const int _FILE_CHANNEL_WAIT_TIMEOUT_SECONDS = 10;
  static const int _FILE_CHANNEL_POLL_INTERVAL_MS = 100;
  // Quality tier bitrate/fps/scale factors
  static const double _TIER1_BITRATE_FACTOR = 0.6;
  static const double _TIER1_FPS_FACTOR = 0.8;
  static const double _TIER1_SCALE = 1.5;
  static const double _TIER2_BITRATE_FACTOR = 0.35;
  static const double _TIER2_FPS_FACTOR = 0.5;
  static const double _TIER2_SCALE = 2.25;
  static const int _TIER3_BITRATE_KBPS = 300;
  static const int _TIER3_FPS = 10;
  static const double _TIER3_SCALE = 3.0;
  static const int _MIN_BITRATE_KBPS = 300;
  static const int _MIN_FPS_LOW_QUALITY = 10;
  static const int _MIN_FPS_MID_QUALITY = 15;
  static const int _MAX_FPS = 30;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _controlChannel;
  RTCDataChannel? _fileTransferChannel;
  MediaStream? _remoteStream;
  MediaStream? _localScreenStream;

  // Video sender – kept so encoder parameters can be updated live
  RTCRtpSender? _videoSender;

  // Adaptive quality state
  bool _autoQuality = false;
  int _baseBitrateKbps = _DEFAULT_BITRATE_KBPS;
  int _baseFps = _DEFAULT_FPS;
  int _qualityTier = 0; // 0 = best quality
  int _consecutiveGoodPolls = 0;
  int _consecutiveBadPolls = 0;
  Timer? _adaptiveQualityTimer;

  final _onQualityChangeController = StreamController<String>.broadcast();

  final _onMessageController =
      StreamController<String>.broadcast(); // For control messages
  final _onFileChunkController =
      StreamController<List<int>>.broadcast(); // For binary file data
  final _onFileMessageController =
      StreamController<String>.broadcast(); // For file channel control messages
  final _onFileChannelStateController =
      StreamController<RTCDataChannelState>.broadcast();
  final _onStateChangeController =
      StreamController<RTCPeerConnectionState>.broadcast();
  final _onIceConnectionStateController =
      StreamController<RTCIceConnectionState>.broadcast();
  final _onIceCandidateController =
      StreamController<RTCIceCandidate>.broadcast();
  final _onRemoteStreamController = StreamController<MediaStream>.broadcast();

  Stream<String> get onMessage => _onMessageController.stream;
  Stream<List<int>> get onFileChunk => _onFileChunkController.stream;
  Stream<String> get onFileMessage => _onFileMessageController.stream;
  Stream<RTCDataChannelState> get onFileChannelState =>
      _onFileChannelStateController.stream;
  Stream<RTCPeerConnectionState> get onStateChange =>
      _onStateChangeController.stream;
  Stream<RTCIceConnectionState> get onIceConnectionState =>
      _onIceConnectionStateController.stream;
  Stream<RTCIceCandidate> get onIceCandidate =>
      _onIceCandidateController.stream;
  Stream<MediaStream> get onRemoteStream => _onRemoteStreamController.stream;
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localScreenStream => _localScreenStream;

  /// Emits a human-readable string whenever adaptive quality changes tier.
  Stream<String> get onQualityChange => _onQualityChangeController.stream;

  bool get isConnected =>
      _peerConnection?.connectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  // Buffered amount support
  int? get fileChannelBufferedAmount => _fileTransferChannel?.bufferedAmount;

  void setFileChannelBufferedAmountLowThreshold(int threshold) {
    _fileTransferChannel?.bufferedAmountLowThreshold = threshold;
  }

  void setOnFileChannelBufferedAmountLow(Function() callback) {
    _fileTransferChannel?.onBufferedAmountLow = (amount) {
      callback();
    };
  }

  Future<void> initialize() async {
    _log.info('WebRTC: Initializing...');
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _log.info('WebRTC: Calling createPeerConnection...');
    _peerConnection = await createPeerConnection(config);
    _log.info('WebRTC: PeerConnection created.');

    _peerConnection!.onConnectionState = (state) {
      _log.info('WebRTC: Connection State changed to $state');
      Future(() => _onStateChangeController.add(state));
    };

    _peerConnection!.onIceConnectionState = (state) {
      _log.info('WebRTC: ICE Connection State changed to $state');
      Future(() => _onIceConnectionStateController.add(state));
    };

    _peerConnection!.onSignalingState = (state) {
      _log.info('WebRTC: Signaling State changed to $state');
    };

    _peerConnection!.onIceCandidate = (candidate) {
      _log.info('WebRTC: Generated ICE Candidate: ${candidate.candidate}');
      Future(() => _onIceCandidateController.add(candidate));
    };

    _peerConnection!.onDataChannel = (channel) {
      _setupIncomingChannel(channel);
    };

    _peerConnection!.onTrack = (event) {
      final streams = event.streams;
      if (streams.isNotEmpty) {
        _remoteStream = streams.first;
        Future(() => _onRemoteStreamController.add(streams.first));
      }
    };

    _log.info('WebRTC: Initialization complete.');
  }

  void _setupIncomingChannel(RTCDataChannel channel) {
    _log.info('WebRTC: Received DataChannel: ${channel.label}');
    if (channel.label == 'control') {
      _controlChannel = channel;
      _setupControlChannel(channel);
    } else if (channel.label == 'file_transfer') {
      _fileTransferChannel = channel;
      _setupFileChannel(channel);
    }
  }

  /// Create offer (initiator side)
  Future<RTCSessionDescription> createOffer() async {
    _log.info('WebRTC: createOffer called');
    if (_peerConnection == null) await initialize();

    // Create Control Channel
    _log.info('WebRTC: Creating control channel...');
    final controlInit = RTCDataChannelInit()..ordered = true;
    _controlChannel = await _peerConnection!.createDataChannel(
      'control',
      controlInit,
    );
    _setupControlChannel(_controlChannel!);

    // Create File Transfer Channel upfront
    _log.info('WebRTC: Creating file transfer channel...');
    final fileInit = RTCDataChannelInit()..ordered = true;
    _fileTransferChannel = await _peerConnection!.createDataChannel(
      'file_transfer',
      fileInit,
    );
    _setupFileChannel(_fileTransferChannel!);

    _log.info('WebRTC: Channels created. Creating offer SDP...');
    final offer = await _peerConnection!.createOffer();
    _log.info('WebRTC: Offer SDP created. Setting local description...');
    await _peerConnection!.setLocalDescription(offer);
    _log.info('WebRTC: Local description set.');
    return offer;
  }

  /// Create file transfer channel on demand
  Future<void> createFileTransferChannel() async {
    if (_peerConnection == null) return;
    if (_fileTransferChannel != null) return; // Already created

    _log.info('WebRTC: Creating file transfer channel on demand...');
    final fileInit = RTCDataChannelInit()..ordered = true;
    _fileTransferChannel = await _peerConnection!.createDataChannel(
      'file_transfer',
      fileInit,
    );
    _setupFileChannel(_fileTransferChannel!);
    _log.info('WebRTC: File transfer channel created.');
  }

  /// Handle offer and create answer (responder side)
  Future<RTCSessionDescription> createAnswer(
    RTCSessionDescription offer,
  ) async {
    if (_peerConnection == null) await initialize();

    await _peerConnection!.setRemoteDescription(offer);
    // onDataChannel will fire when channels are established

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  /// Set remote answer (initiator side)
  Future<void> setRemoteAnswer(RTCSessionDescription answer) async {
    await _peerConnection?.setRemoteDescription(answer);
  }

  Future<RTCSessionDescription> createRenegotiationOffer() async {
    if (_peerConnection == null) {
      throw Exception('PeerConnection is not initialized');
    }

    final offer = await _peerConnection!.createOffer();

    // Fix C: annotate bandwidth ceiling in the video m-section
    final rawSdp = offer.sdp ?? '';
    final mungedSdp = _mungeSdpBandwidth(rawSdp, _baseBitrateKbps);
    final mungedOffer = RTCSessionDescription(mungedSdp, offer.type);
    await _peerConnection!.setLocalDescription(mungedOffer);
    return mungedOffer;
  }

  /// Start capturing the local screen and add it as a video track.
  ///
  /// [bitrateKbps] – null enables automatic adaptive quality control;
  /// a positive integer fixes the encoder to that bitrate ceiling.
  /// Resolution is capped at 1080p; framerate uses hard min/max bounds (Fix B).
  Future<void> startScreenCapture({
    required String sourceId,
    required int fps,
    int? bitrateKbps,
  }) async {
    if (_peerConnection == null) {
      throw Exception('PeerConnection is not initialized');
    }

    _baseFps = fps;
    _baseBitrateKbps = bitrateKbps ?? _DEFAULT_BITRATE_KBPS;
    _autoQuality = bitrateKbps == null;

    // Stop any existing stream
    stopAdaptiveQuality();
    if (_localScreenStream != null) {
      for (final track in _localScreenStream!.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      _localScreenStream = null;
      _videoSender = null;
    }

    MediaStream? stream;
    Object? lastError;

    // Fix B: hard maxFrameRate bounds + 1080p cap
    final desktopConstraints = <String, dynamic>{
      'audio': false,
      'video': {
        'deviceId': {'exact': sourceId},
        'mandatory': {
          'maxWidth': _MAX_WIDTH,
          'maxHeight': _MAX_HEIGHT,
          'maxFrameRate': fps.toDouble(),
          'minFrameRate': _MIN_FRAMERATE,
        },
      },
    };

    final legacyConstraints = <String, dynamic>{
      'audio': false,
      'video': {
        'maxWidth': _MAX_WIDTH,
        'maxHeight': _MAX_HEIGHT,
        'maxFrameRate': fps,
        'sourceId': sourceId,
      },
    };

    // Bounded generic fallback — still caps resolution and fps
    final genericFallbackConstraints = <String, dynamic>{
      'audio': false,
      'video': {
        'mandatory': {
          'maxWidth': _MAX_WIDTH,
          'maxHeight': _MAX_HEIGHT,
          'maxFrameRate': fps.toDouble(),
        },
      },
    };

    for (final attempt in [
      desktopConstraints,
      legacyConstraints,
      genericFallbackConstraints,
    ]) {
      try {
        stream = await navigator.mediaDevices.getDisplayMedia(attempt);
        break;
      } catch (error) {
        lastError = error;
        _log.warning('WebRTC: getDisplayMedia attempt failed: $error');
      }
    }

    if (stream == null) {
      throw Exception('Unable to getDisplayMedia after retries: $lastError');
    }

    _localScreenStream = stream;

    for (final track in stream.getVideoTracks()) {
      _videoSender = await _peerConnection!.addTrack(track, stream);
    }

    // Apply encoder constraints immediately
    if (!_autoQuality) {
      await _applyEncoderParams(
        bitrateKbps: _baseBitrateKbps,
        fps: fps,
        scaleDown: 1.0,
      );
    } else {
      _startAdaptiveQuality();
    }
  }

  /// Stop local screen capture and remove the outbound video sender.
  Future<void> stopScreenCapture() async {
    stopAdaptiveQuality();

    final sender = _videoSender;
    if (_peerConnection != null && sender != null) {
      try {
        await _peerConnection!.removeTrack(sender);
      } catch (e) {
        _log.warning('WebRTC: removeTrack failed while stopping capture: $e');
      }
    }

    if (_localScreenStream != null) {
      for (final track in _localScreenStream!.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      _localScreenStream = null;
    }

    _videoSender = null;
  }

  /// Add ICE candidate from peer
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _peerConnection?.addCandidate(candidate);
  }

  /// Send control message (JSON/Text)
  Future<void> sendControlMessage(String message) => sendMessage(message);

  Future<void> sendMessage(String message) async {
    if (_controlChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      await _controlChannel!.send(RTCDataChannelMessage(message));
    } else {
      _log.warning('WebRTC Warning: Control channel not open');
    }
  }

  /// Send file chunk (Binary)
  Future<void> sendFileChunk(List<int> data) async {
    if (_fileTransferChannel == null) {
      throw Exception('File transfer channel not initialized');
    }

    if (_fileTransferChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      _log.info(
        'WebRTC: Waiting for file channel to open '
        '(Current: ${_fileTransferChannel!.state})...',
      );
      await _waitForFileChannelOpen();
    }

    await _fileTransferChannel!.send(
      RTCDataChannelMessage.fromBinary(Uint8List.fromList(data)),
    );
  }

  /// Send file channel control message (JSON/Text)
  Future<void> sendFileMessage(String message) async {
    if (_fileTransferChannel == null) {
      throw Exception('File transfer channel not initialized');
    }

    if (_fileTransferChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      _log.info(
        'WebRTC: Waiting for file channel to open '
        '(Current: ${_fileTransferChannel!.state})...',
      );
      await _waitForFileChannelOpen();
    }

    await _fileTransferChannel!.send(RTCDataChannelMessage(message));
  }

  Future<void> _waitForFileChannelOpen() async {
    if (_fileTransferChannel == null) return;
    if (_fileTransferChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }

    final waitForOpen = onFileChannelState.firstWhere(
      (state) => state == RTCDataChannelState.RTCDataChannelOpen,
    );

    final pollCompleter = Completer<void>();
    Timer? timer;
    try {
      timer = Timer.periodic(
        const Duration(milliseconds: _FILE_CHANNEL_POLL_INTERVAL_MS),
        (t) {
          if (_fileTransferChannel?.state ==
              RTCDataChannelState.RTCDataChannelOpen) {
            if (!pollCompleter.isCompleted) {
              pollCompleter.complete();
            }
            t.cancel();
          }
        },
      );

      await Future.any([waitForOpen, pollCompleter.future]).timeout(
        const Duration(seconds: _FILE_CHANNEL_WAIT_TIMEOUT_SECONDS),
        onTimeout: () {
          throw Exception('Timeout waiting for file transfer channel to open');
        },
      );
    } finally {
      timer?.cancel();
    }
  }

  void _setupControlChannel(RTCDataChannel channel) {
    channel.onMessage = (message) {
      if (!message.isBinary) {
        Future(() => _onMessageController.add(message.text));
      }
    };
  }

  void _setupFileChannel(RTCDataChannel channel) {
    channel.onMessage = (message) {
      if (message.isBinary) {
        Future(() => _onFileChunkController.add(message.binary));
      } else {
        Future(() => _onFileMessageController.add(message.text));
      }
    };
    channel.onDataChannelState = (state) {
      Future(() => _onFileChannelStateController.add(state));
    };
  }

  // ─── Encoder parameter control ─────────────────────────────────────────

  /// Directly update the live bitrate without renegotiation.
  Future<void> updateBitrate(int bitrateKbps) async {
    _baseBitrateKbps = bitrateKbps;
    _autoQuality = false;
    stopAdaptiveQuality();
    await _applyEncoderParams(
      bitrateKbps: bitrateKbps,
      fps: _baseFps,
      scaleDown: 1.0,
    );
  }

  Future<void> _applyEncoderParams({
    required int bitrateKbps,
    required int fps,
    required double scaleDown,
  }) async {
    final sender = _videoSender;
    if (sender == null) return;
    try {
      final params = RTCRtpParameters(
        encodings: [
          RTCRtpEncoding(
            active: true,
            maxBitrate: bitrateKbps * _KBPS_TO_BPS_MULTIPLIER,
            maxFramerate: fps,
            scaleResolutionDownBy: scaleDown,
          ),
        ],
      );
      await sender.setParameters(params);
      _log.info(
        'WebRTC: Encoder params set — '
        '${bitrateKbps}kbps, ${fps}fps, scale×$scaleDown',
      );
    } catch (e) {
      _log.warning('WebRTC: setParameters failed: $e');
    }
  }

  // ─── Adaptive quality ────────────────────────────────────────────────────

  void _startAdaptiveQuality() {
    _qualityTier = 0;
    _consecutiveGoodPolls = 0;
    _consecutiveBadPolls = 0;
    _adaptiveQualityTimer?.cancel();
    _adaptiveQualityTimer = Timer.periodic(
      const Duration(seconds: _ADAPTIVE_QUALITY_POLL_INTERVAL_SECONDS),
      (_) => _checkAndAdaptQuality(),
    );
    _log.info('WebRTC: Adaptive quality monitoring started');
  }

  void stopAdaptiveQuality() {
    _adaptiveQualityTimer?.cancel();
    _adaptiveQualityTimer = null;
  }

  Future<void> _checkAndAdaptQuality() async {
    if (_peerConnection == null || _videoSender == null) return;
    try {
      final stats = await _peerConnection!.getStats(null);
      double fractionLost = -1;
      double rtt = -1;
      String limitReason = 'none';

      for (final report in stats) {
        final v = report.values;
        if (report.type == 'remote-inbound-rtp') {
          fractionLost =
              (v['fractionLost'] as num?)?.toDouble() ??
              (v['fraction-lost'] as num?)?.toDouble() ??
              fractionLost;
          rtt =
              (v['roundTripTime'] as num?)?.toDouble() ??
              (v['round-trip-time'] as num?)?.toDouble() ??
              rtt;
        }
        if (report.type == 'outbound-rtp' &&
            (v['mediaType'] == 'video' || v['kind'] == 'video')) {
          limitReason =
              (v['qualityLimitationReason'] as String?) ?? limitReason;
        }
      }

      // No usable stats yet — skip
      if (fractionLost < 0) return;

      final isBad =
          fractionLost > _QUALITY_BAD_FRACTION_LOST_THRESHOLD ||
          (rtt >= 0 && rtt > _QUALITY_BAD_RTT_THRESHOLD) ||
          limitReason == 'bandwidth' ||
          limitReason == 'cpu';
      final isGood =
          fractionLost < _QUALITY_GOOD_FRACTION_LOST_THRESHOLD &&
          (rtt < 0 || rtt < _QUALITY_GOOD_RTT_THRESHOLD) &&
          limitReason == 'none';

      if (isBad) {
        _consecutiveBadPolls++;
        _consecutiveGoodPolls = 0;
        if (_consecutiveBadPolls >= _CONSECUTIVE_BAD_POLLS_FOR_DOWNGRADE &&
            _qualityTier < _QUALITY_TIER_MAX) {
          _qualityTier++;
          _consecutiveBadPolls = 0;
          await _applyQualityTier();
        }
      } else if (isGood) {
        _consecutiveGoodPolls++;
        _consecutiveBadPolls = 0;
        // Require N consecutive good polls before upgrading to avoid flapping
        if (_consecutiveGoodPolls >= _CONSECUTIVE_GOOD_POLLS_FOR_UPGRADE &&
            _qualityTier > 0) {
          _qualityTier--;
          _consecutiveGoodPolls = 0;
          await _applyQualityTier();
        }
      } else {
        _consecutiveGoodPolls = 0;
        _consecutiveBadPolls = 0;
      }
    } catch (e) {
      _log.warning('WebRTC: Adaptive quality stats check failed: $e');
    }
  }

  Future<void> _applyQualityTier() async {
    late int kbps;
    late int fps;
    late double scale;
    late String label;

    switch (_qualityTier) {
      case 0:
        kbps = _baseBitrateKbps;
        fps = _baseFps;
        scale = 1.0;
        label = '1080p';
      case 1:
        kbps = (_baseBitrateKbps * _TIER1_BITRATE_FACTOR).round().clamp(
          _MIN_BITRATE_KBPS,
          _baseBitrateKbps,
        );
        fps = (_baseFps * _TIER1_FPS_FACTOR).round().clamp(
          _MIN_FPS_MID_QUALITY,
          _MAX_FPS,
        );
        scale = _TIER1_SCALE; // ~720p from 1080p source
        label = '720p';
      case 2:
        kbps = (_baseBitrateKbps * _TIER2_BITRATE_FACTOR).round().clamp(
          _MIN_BITRATE_KBPS,
          _baseBitrateKbps,
        );
        fps = (_baseFps * _TIER2_FPS_FACTOR).round().clamp(
          _MIN_FPS_LOW_QUALITY,
          20,
        );
        scale = _TIER2_SCALE; // ~480p from 1080p source
        label = '480p';
      default: // tier 3 — minimum footprint
        kbps = _TIER3_BITRATE_KBPS;
        fps = _TIER3_FPS;
        scale = _TIER3_SCALE; // ~360p from 1080p source
        label = '360p';
    }

    await _applyEncoderParams(bitrateKbps: kbps, fps: fps, scaleDown: scale);

    final msg = 'Auto quality → $label (${kbps}kbps, ${fps}fps)';
    _log.info('WebRTC: $msg');
    if (!_onQualityChangeController.isClosed) {
      _onQualityChangeController.add(msg);
    }
  }

  // ─── SDP bandwidth annotation (Fix C) ────────────────────────────────────

  /// Injects b=AS and b=TIAS into the video m-section of an SDP blob.
  static String _mungeSdpBandwidth(String sdp, int bitrateKbps) {
    final lines = sdp.split('\r\n');
    final result = <String>[];
    bool inVideo = false;
    for (final line in lines) {
      if (line.startsWith('m=video')) {
        inVideo = true;
      } else if (line.startsWith('m=')) {
        inVideo = false;
      }
      // Drop any pre-existing b= lines in the video section
      if (inVideo && line.startsWith('b=')) continue;
      result.add(line);
      // Insert immediately after the connection line
      if (inVideo && line.startsWith('c=')) {
        result.add('b=AS:$bitrateKbps');
        result.add('b=TIAS:${bitrateKbps * _KBPS_TO_BPS_MULTIPLIER}');
      }
    }
    return result.join('\r\n');
  }

  Future<void> dispose() async {
    stopAdaptiveQuality();
    if (_localScreenStream != null) {
      for (final track in _localScreenStream!.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      _localScreenStream = null;
      _videoSender = null;
    }
    await _controlChannel?.close();
    await _fileTransferChannel?.close();
    await _peerConnection?.close();
    await _onMessageController.close();
    await _onFileChunkController.close();
    await _onFileMessageController.close();
    await _onFileChannelStateController.close();
    await _onStateChangeController.close();
    await _onIceConnectionStateController.close();
    await _onIceCandidateController.close();
    await _onRemoteStreamController.close();
    await _onQualityChangeController.close();
  }
}

/// Signaling message types
class SignalingMessage {
  final String type; // 'offer', 'answer', 'ice'
  final Map<String, dynamic> data;

  SignalingMessage({required this.type, required this.data});

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    return SignalingMessage(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() => {'type': type, 'data': data};

  String toJsonString() => jsonEncode(toJson());

  static SignalingMessage fromJsonString(String json) {
    return SignalingMessage.fromJson(jsonDecode(json));
  }
}
