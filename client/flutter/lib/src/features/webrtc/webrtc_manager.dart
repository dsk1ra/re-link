import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

enum _AutoQualityProfile { stable, recovery, minimum }

/// Manages WebRTC peer connection with minimal signaling
class WebRTCManager {
  static final Logger _log = Logger('WebRTCManager');

  WebRTCManager({List<Map<String, dynamic>>? iceServers})
    : _iceServers = iceServers;

  final List<Map<String, dynamic>>? _iceServers;

  // ─── Magic number constants ────────────────────────────────────────────
  static const int _KBPS_TO_BPS_MULTIPLIER = 1000;
  static const int _DEFAULT_BITRATE_KBPS = 2000;
  static const int _DEFAULT_FPS = 30;
  static const int _MIN_FRAMERATE = 1;
  static const int _MAX_WIDTH = 1920;
  static const int _MAX_HEIGHT = 1080;
  static const int _FILE_CHANNEL_WAIT_TIMEOUT_SECONDS = 10;
  static const int _AUTO_QUALITY_SAMPLE_INTERVAL_MS = 1000;
  // Auto-quality fallback profiles for transport disruptions.
  static const double _RECOVERY_BITRATE_FACTOR = 0.6;
  static const double _RECOVERY_FPS_FACTOR = 0.8;
  static const double _RECOVERY_SCALE = 1.5;
  static const double _MINIMUM_BITRATE_FACTOR = 0.35;
  static const double _MINIMUM_FPS_FACTOR = 0.5;
  static const double _MINIMUM_SCALE = 2.25;
  static const double _BAD_FRACTION_LOST_THRESHOLD = 0.05;
  static const double _GOOD_FRACTION_LOST_THRESHOLD = 0.01;
  static const double _BAD_RTT_THRESHOLD = 0.5;
  static const double _GOOD_RTT_THRESHOLD = 0.2;
  static const int _BAD_SAMPLES_FOR_DOWNGRADE = 2;
  static const int _GOOD_SAMPLES_FOR_UPGRADE = 4;
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

  // Auto quality state
  bool _autoQuality = false;
  int _baseBitrateKbps = _DEFAULT_BITRATE_KBPS;
  int _baseFps = _DEFAULT_FPS;
  _AutoQualityProfile? _autoQualityProfile;
  int _consecutiveBadSamples = 0;
  int _consecutiveGoodSamples = 0;
  Timer? _autoQualityTimer;

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

  /// Emits a human-readable string whenever auto quality changes profile.
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
    final iceServers = (_iceServers?.isNotEmpty ?? false)
        ? _iceServers
        : [
            {'urls': 'stun:localhost:3478'},
          ];

    final config = {'iceServers': iceServers, 'sdpSemantics': 'unified-plan'};

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
  /// [bitrateKbps] – null enables native auto quality control;
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
      await _startAdaptiveQuality();
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

    final completer = Completer<void>();

    final subscription = onFileChannelState.listen((state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          !completer.isCompleted) {
        completer.complete();
      }
    });

    // Double-check the state after subscribing to avoid dropping the event.
    if (_fileTransferChannel!.state == RTCDataChannelState.RTCDataChannelOpen &&
        !completer.isCompleted) {
      completer.complete();
    }

    try {
      await completer.future.timeout(
        const Duration(seconds: _FILE_CHANNEL_WAIT_TIMEOUT_SECONDS),
      );
    } on TimeoutException {
      throw Exception('Timeout waiting for file transfer channel to open');
    } finally {
      subscription.cancel();
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
    RTCDegradationPreference? degradationPreference,
  }) async {
    final sender = _videoSender;
    if (sender == null) return;
    try {
      final params = sender.parameters;
      final encoding = params.encodings != null && params.encodings!.isNotEmpty
          ? params.encodings!.first
          : RTCRtpEncoding();
      encoding.active = true;
      encoding.maxBitrate = bitrateKbps * _KBPS_TO_BPS_MULTIPLIER;
      encoding.maxFramerate = fps;
      encoding.scaleResolutionDownBy = scaleDown;
      params.encodings = [encoding];
      params.degradationPreference = degradationPreference;
      await sender.setParameters(params);
      _log.info(
        'WebRTC: Encoder params set — '
        '${bitrateKbps}kbps, ${fps}fps, scale×$scaleDown',
      );
    } catch (e) {
      _log.warning('WebRTC: setParameters failed: $e');
    }
  }

  // ─── Auto quality ────────────────────────────────────────────────────────

  Future<void> _startAdaptiveQuality() async {
    stopAdaptiveQuality();
    _autoQualityProfile = null;
    _consecutiveBadSamples = 0;
    _consecutiveGoodSamples = 0;
    await _applyAutoQualityProfile(_AutoQualityProfile.stable, force: true);
    _autoQualityTimer = Timer.periodic(
      const Duration(milliseconds: _AUTO_QUALITY_SAMPLE_INTERVAL_MS),
      (_) => unawaited(_sampleAndAdaptQuality()),
    );
    _log.info('WebRTC: Stats-based auto quality monitoring started');
  }

  void stopAdaptiveQuality() {
    _autoQualityTimer?.cancel();
    _autoQualityTimer = null;
    _autoQualityProfile = null;
    _consecutiveBadSamples = 0;
    _consecutiveGoodSamples = 0;
  }

  Future<void> _sampleAndAdaptQuality() async {
    final peerConnection = _peerConnection;
    final sender = _videoSender;
    if (!_autoQuality || peerConnection == null || sender == null) return;

    try {
      var stats = await peerConnection.getStats(sender.track);
      double fractionLost = -1;
      double rtt = -1;
      String limitReason = 'none';

      for (final report in stats) {
        final values = report.values;
        if (report.type == 'remote-inbound-rtp') {
          fractionLost =
              (values['fractionLost'] as num?)?.toDouble() ??
              (values['fraction-lost'] as num?)?.toDouble() ??
              fractionLost;
          rtt =
              (values['roundTripTime'] as num?)?.toDouble() ??
              (values['round-trip-time'] as num?)?.toDouble() ??
              rtt;
        }
        if (report.type == 'outbound-rtp' &&
            (values['mediaType'] == 'video' || values['kind'] == 'video')) {
          limitReason =
              (values['qualityLimitationReason'] as String?) ?? limitReason;
        }
      }

      // Some platforms omit track-scoped remote stats; fall back to broader stats.
      if (fractionLost < 0 && rtt < 0) {
        stats = await peerConnection.getStats();
        for (final report in stats) {
          final values = report.values;
          if (report.type == 'remote-inbound-rtp') {
            fractionLost =
                (values['fractionLost'] as num?)?.toDouble() ??
                (values['fraction-lost'] as num?)?.toDouble() ??
                fractionLost;
            rtt =
                (values['roundTripTime'] as num?)?.toDouble() ??
                (values['round-trip-time'] as num?)?.toDouble() ??
                rtt;
          }
          if (report.type == 'outbound-rtp' &&
              (values['mediaType'] == 'video' || values['kind'] == 'video')) {
            limitReason =
                (values['qualityLimitationReason'] as String?) ?? limitReason;
          }
        }
      }

      final hasLoss = fractionLost >= 0;
      final hasRtt = rtt >= 0;
      if (!hasLoss && !hasRtt && limitReason == 'none') {
        return;
      }

      final isBad =
          (hasLoss && fractionLost > _BAD_FRACTION_LOST_THRESHOLD) ||
          (hasRtt && rtt > _BAD_RTT_THRESHOLD) ||
          limitReason == 'bandwidth' ||
          limitReason == 'cpu';
      final isGood =
          (!hasLoss || fractionLost < _GOOD_FRACTION_LOST_THRESHOLD) &&
          (!hasRtt || rtt < _GOOD_RTT_THRESHOLD) &&
          limitReason == 'none';

      if (isBad) {
        _consecutiveBadSamples++;
        _consecutiveGoodSamples = 0;
        if (_consecutiveBadSamples >= _BAD_SAMPLES_FOR_DOWNGRADE) {
          _consecutiveBadSamples = 0;
          final nextProfile = switch (_autoQualityProfile) {
            _AutoQualityProfile.stable => _AutoQualityProfile.recovery,
            _AutoQualityProfile.recovery => _AutoQualityProfile.minimum,
            _AutoQualityProfile.minimum => _AutoQualityProfile.minimum,
            null => _AutoQualityProfile.recovery,
          };
          await _applyAutoQualityProfile(nextProfile);
        }
        return;
      }

      if (isGood) {
        _consecutiveGoodSamples++;
        _consecutiveBadSamples = 0;
        if (_consecutiveGoodSamples >= _GOOD_SAMPLES_FOR_UPGRADE) {
          _consecutiveGoodSamples = 0;
          final nextProfile = switch (_autoQualityProfile) {
            _AutoQualityProfile.minimum => _AutoQualityProfile.recovery,
            _AutoQualityProfile.recovery => _AutoQualityProfile.stable,
            _AutoQualityProfile.stable => _AutoQualityProfile.stable,
            null => _AutoQualityProfile.stable,
          };
          await _applyAutoQualityProfile(nextProfile);
        }
        return;
      }

      _consecutiveBadSamples = 0;
      _consecutiveGoodSamples = 0;
    } catch (e) {
      _log.warning('WebRTC: Auto quality stats sampling failed: $e');
    }
  }

  Future<void> _applyAutoQualityProfile(
    _AutoQualityProfile profile, {
    bool force = false,
  }) async {
    if (!force && _autoQualityProfile == profile) return;

    late int kbps;
    late int fps;
    late double scale;
    late String label;
    late RTCDegradationPreference degradationPreference;

    switch (profile) {
      case _AutoQualityProfile.stable:
        kbps = _baseBitrateKbps;
        fps = _baseFps;
        scale = 1.0;
        label = '1080p';
        degradationPreference = RTCDegradationPreference.BALANCED;
        break;
      case _AutoQualityProfile.recovery:
        kbps = (_baseBitrateKbps * _RECOVERY_BITRATE_FACTOR).round().clamp(
          _MIN_BITRATE_KBPS,
          _baseBitrateKbps,
        );
        fps = (_baseFps * _RECOVERY_FPS_FACTOR).round().clamp(
          _MIN_FPS_MID_QUALITY,
          _MAX_FPS,
        );
        scale = _RECOVERY_SCALE;
        label = '720p';
        degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
        break;
      case _AutoQualityProfile.minimum:
        kbps = (_baseBitrateKbps * _MINIMUM_BITRATE_FACTOR).round().clamp(
          _MIN_BITRATE_KBPS,
          _baseBitrateKbps,
        );
        fps = (_baseFps * _MINIMUM_FPS_FACTOR).round().clamp(
          _MIN_FPS_LOW_QUALITY,
          20,
        );
        scale = _MINIMUM_SCALE;
        label = '480p';
        degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
        break;
    }

    await _applyEncoderParams(
      bitrateKbps: kbps,
      fps: fps,
      scaleDown: scale,
      degradationPreference: degradationPreference,
    );
    _autoQualityProfile = profile;

    final msg = 'Auto quality → $label (${kbps}kbps, ${fps}fps)';
    _log.info('WebRTC: $msg');
    if (!_onQualityChangeController.isClosed) {
      _onQualityChangeController.add(msg);
    }
  }

  // ─── SDP bandwidth annotation (Fix C) ────────────────────────────────────

  /// Injects b=AS and b=TIAS into the video m-section of an SDP blob.
  String _mungeSdpBandwidth(String sdp, int bitrateKbps) {
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
