import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:application/src/rust/api/share.dart' as rust_share;
import 'package:application/src/rust/api/webrtc.dart' as rust_webrtc;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:logging/logging.dart';

enum RTCPeerConnectionState {
  RTCPeerConnectionStateNew,
  RTCPeerConnectionStateConnecting,
  RTCPeerConnectionStateConnected,
  RTCPeerConnectionStateDisconnected,
  RTCPeerConnectionStateFailed,
  RTCPeerConnectionStateClosed,
}

enum RTCDataChannelState {
  RTCDataChannelStateConnecting,
  RTCDataChannelStateOpen,
  RTCDataChannelStateClosing,
  RTCDataChannelStateClosed,
}

class RTCSessionDescription {
  RTCSessionDescription(this.sdp, this.type);

  final String sdp;
  final String type;
}

class RTCIceCandidate {
  RTCIceCandidate(this.candidate, this.sdpMid, this.sdpMLineIndex);

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

class ScreenShareQualityStatus {
  const ScreenShareQualityStatus({
    required this.width,
    required this.height,
    required this.fps,
    required this.bitrateKbps,
    required this.autoQuality,
    required this.qualityLabel,
  });

  final int width;
  final int height;
  final int fps;
  final int bitrateKbps;
  final bool autoQuality;
  final String qualityLabel;

  String get resolutionLabel => '${width}x$height';
}

class WebRTCManager {
  static final Logger _log = Logger('WebRTCManager');

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
  static const int _TIER3_BITRATE_KBPS = 300;
  static const int _TIER3_FPS = 10;
  static const int _MIN_BITRATE_KBPS = 300;
  static const int _MIN_FPS_LOW_QUALITY = 10;
  static const int _MIN_FPS_MID_QUALITY = 15;
  static const int _MAX_FPS = 30;
  static const double _TIER1_BITRATE_FACTOR = 0.6;
  static const double _TIER1_FPS_FACTOR = 0.8;
  static const double _TIER1_SCALE = 1.5;
  static const double _TIER2_BITRATE_FACTOR = 0.35;
  static const double _TIER2_FPS_FACTOR = 0.5;
  static const double _TIER2_SCALE = 2.25;
  static const double _TIER3_SCALE = 3.0;

  static const String _screenShareOfferType = 'screen_share_offer';
  static const String _screenShareAnswerType = 'screen_share_answer';
  static const String _screenShareIceType = 'screen_share_ice';
  static const String _screenShareStoppedType = 'screen_share_stopped';

  WebRTCManager({
    required String connectionId,
    List<Map<String, dynamic>>? iceServers,
  }) : _connectionId = connectionId,
       _iceServers = iceServers;

  final String _connectionId;
  final List<Map<String, dynamic>>? _iceServers;

  String get connectionId => _connectionId;

  final _onScreenShareStatusController =
      StreamController<ScreenShareQualityStatus>.broadcast();
  final _onScreenShareStoppedController = StreamController<bool>.broadcast();
  final _onRemoteMediaStateController = StreamController<String>.broadcast();
  final _onMessageController = StreamController<String>.broadcast();
  final _onFileChunkController = StreamController<List<int>>.broadcast();
  final _onFileMessageController = StreamController<String>.broadcast();
  final _onRenegotiationOfferController =
      StreamController<RTCSessionDescription>.broadcast();
  final _onRenegotiationAnswerController =
      StreamController<RTCSessionDescription>.broadcast();
  final _onRenegotiationIceController =
      StreamController<RTCIceCandidate>.broadcast();
  final _onPeerSessionClosedController = StreamController<bool>.broadcast();
  final _onSessionClosedAckController = StreamController<String?>.broadcast();
  final _onPongController = StreamController<String?>.broadcast();
  final _onFileTransferRequestedController = StreamController<bool>.broadcast();
  final _onFileChannelStateController =
      StreamController<RTCDataChannelState>.broadcast();
  final _onStateChangeController =
      StreamController<RTCPeerConnectionState>.broadcast();
  final _onIceCandidateController =
      StreamController<RTCIceCandidate>.broadcast();
  final _onRemoteStreamController =
      StreamController<rtc.MediaStream>.broadcast();

  Stream<String> get onMessage => _onMessageController.stream;
  Stream<bool> get onScreenShareStopped =>
      _onScreenShareStoppedController.stream;
  Stream<String> get onRemoteMediaState => _onRemoteMediaStateController.stream;
  Stream<List<int>> get onFileChunk => _onFileChunkController.stream;
  Stream<String> get onFileMessage => _onFileMessageController.stream;
  Stream<RTCSessionDescription> get onRenegotiationOffer =>
      _onRenegotiationOfferController.stream;
  Stream<RTCSessionDescription> get onRenegotiationAnswer =>
      _onRenegotiationAnswerController.stream;
  Stream<RTCIceCandidate> get onRenegotiationIceCandidate =>
      _onRenegotiationIceController.stream;
  Stream<bool> get onPeerSessionClosed => _onPeerSessionClosedController.stream;
  Stream<String?> get onSessionClosedAck =>
      _onSessionClosedAckController.stream;
  Stream<String?> get onPong => _onPongController.stream;
  Stream<bool> get onFileTransferRequested =>
      _onFileTransferRequestedController.stream;
  Stream<RTCDataChannelState> get onFileChannelState =>
      _onFileChannelStateController.stream;
  Stream<RTCPeerConnectionState> get onStateChange =>
      _onStateChangeController.stream;
  Stream<RTCIceCandidate> get onIceCandidate =>
      _onIceCandidateController.stream;
  Stream<ScreenShareQualityStatus> get onScreenShareStatus =>
      _onScreenShareStatusController.stream;
  Stream<rtc.MediaStream> get onRemoteStream =>
      _onRemoteStreamController.stream;

  RTCPeerConnectionState? _lastConnectionState;
  RTCDataChannelState? _lastFileChannelState;
  int _lastFileBufferedAmount = 0;
  Timer? _eventPollTimer;
  bool _eventPollInFlight = false;
  Function()? _onFileBufferedAmountLow;

  rtc.RTCPeerConnection? _screenSharePeerConnection;
  rtc.MediaStream? _localScreenStream;
  rtc.MediaStream? _remoteStream;
  rtc.RTCRtpSender? _videoSender;
  Timer? _adaptiveQualityTimer;
  bool _autoQuality = false;
  int _baseBitrateKbps = _DEFAULT_BITRATE_KBPS;
  int _baseFps = _DEFAULT_FPS;
  int _currentBitrateKbps = _DEFAULT_BITRATE_KBPS;
  int _currentFps = _DEFAULT_FPS;
  double _currentScaleDown = 1.0;
  int _qualityTier = 0;
  int _consecutiveGoodPolls = 0;
  int _consecutiveBadPolls = 0;
  ScreenShareQualityStatus? _currentScreenShareStatus;
  Future<void> _screenControlChain = Future.value();

  bool get isConnected =>
      _lastConnectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  RTCDataChannelState? get fileChannelState => _lastFileChannelState;

  int? get fileChannelBufferedAmount => _lastFileBufferedAmount;

  rtc.MediaStream? get remoteStream => _remoteStream;
  ScreenShareQualityStatus? get currentScreenShareStatus =>
      _currentScreenShareStatus;

  void setFileChannelBufferedAmountLowThreshold(int threshold) {
    unawaited(
      rust_webrtc.setFileBufferedAmountLowThreshold(
        connectionId: _connectionId,
        threshold: BigInt.from(threshold),
      ),
    );
  }

  void setOnFileChannelBufferedAmountLow(Function() callback) {
    _onFileBufferedAmountLow = callback;
  }

  Future<void> initialize() async {
    final rustIceServers = (_iceServers ?? const <Map<String, dynamic>>[])
        .where((server) => server['urls'] != null)
        .map(_toRustIceServer)
        .toList();

    await rust_webrtc.createSession(
      connectionId: _connectionId,
      iceServers: rustIceServers,
    );

    _startEventPolling();
  }

  rust_webrtc.IceServerConfig _toRustIceServer(Map<String, dynamic> server) {
    final urlsRaw = server['urls'];
    final urls = urlsRaw is List
        ? urlsRaw.map((value) => value.toString()).toList()
        : <String>[urlsRaw.toString()];

    return rust_webrtc.IceServerConfig(
      urls: urls,
      username: server['username']?.toString(),
      credential: server['credential']?.toString(),
    );
  }

  Map<String, dynamic> _toFlutterRtcConfiguration() {
    final iceServers = _iceServers;
    final servers = (iceServers == null || iceServers.isEmpty)
        ? <Map<String, dynamic>>[
            {'urls': 'stun:stun.l.google.com:19302'},
          ]
        : iceServers
              .map((server) => Map<String, dynamic>.from(server))
              .toList();

    return {'iceServers': servers, 'sdpSemantics': 'unified-plan'};
  }

  Future<RTCSessionDescription> createOffer() async {
    final offer = await rust_webrtc.createOffer(connectionId: _connectionId);
    return RTCSessionDescription(offer.sdp, offer.kind);
  }

  Future<RTCSessionDescription> createAnswer(
    RTCSessionDescription offer,
  ) async {
    final answer = await rust_webrtc.createAnswer(
      connectionId: _connectionId,
      remoteOffer: rust_webrtc.SessionDescriptionDto(
        kind: offer.type,
        sdp: offer.sdp,
      ),
    );
    return RTCSessionDescription(answer.sdp, answer.kind);
  }

  Future<void> setRemoteAnswer(RTCSessionDescription answer) {
    return rust_webrtc.setRemoteAnswer(
      connectionId: _connectionId,
      remoteAnswer: rust_webrtc.SessionDescriptionDto(
        kind: answer.type,
        sdp: answer.sdp,
      ),
    );
  }

  Future<RTCSessionDescription> createRenegotiationOffer() {
    return createOffer();
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) {
    return rust_webrtc.addIceCandidate(
      connectionId: _connectionId,
      candidate: rust_webrtc.IceCandidateDto(
        candidate: candidate.candidate,
        sdpMid: candidate.sdpMid,
        sdpMlineIndex: candidate.sdpMLineIndex,
      ),
    );
  }

  Future<void> sendMessage(String message) {
    return rust_webrtc.sendControlMessage(
      connectionId: _connectionId,
      message: message,
    );
  }

  Future<void> sendControlMessage(String message) => sendMessage(message);

  Future<void> sendRenegotiationOffer(RTCSessionDescription description) {
    return rust_webrtc.sendRenegotiationOffer(
      connectionId: _connectionId,
      description: rust_webrtc.SessionDescriptionDto(
        kind: description.type,
        sdp: description.sdp,
      ),
    );
  }

  Future<void> sendRenegotiationAnswer(RTCSessionDescription description) {
    return rust_webrtc.sendRenegotiationAnswer(
      connectionId: _connectionId,
      description: rust_webrtc.SessionDescriptionDto(
        kind: description.type,
        sdp: description.sdp,
      ),
    );
  }

  Future<void> sendScreenShareStopped() {
    return rust_webrtc.sendControlMessage(
      connectionId: _connectionId,
      message: '{"type":"$_screenShareStoppedType"}',
    );
  }

  Future<List<rust_share.SourceDescriptor>> listShareSources() async {
    try {
      final sources = await rtc.desktopCapturer.getSources(
        types: <rtc.SourceType>[rtc.SourceType.Screen, rtc.SourceType.Window],
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
    } catch (error) {
      _log.warning(
        'Failed to query desktop sources from flutter_webrtc: $error',
      );
      return const [];
    }
  }

  Future<void> startScreenCapture({
    required String sourceId,
    required int fps,
    int? bitrateKbps,
  }) async {
    if (!isConnected) {
      throw Exception('PeerConnection is not connected');
    }

    _baseFps = fps;
    _baseBitrateKbps = bitrateKbps ?? _DEFAULT_BITRATE_KBPS;
    _autoQuality = bitrateKbps == null;

    stopAdaptiveQuality();
    await _closeScreenSharePeerConnection(
      clearRemoteStream: false,
      stopLocalStream: true,
    );

    final stream = await _getDisplayMediaStream(sourceId: sourceId, fps: fps);
    final pc = await _createScreenSharePeerConnection();
    _localScreenStream = stream;

    for (final track in stream.getVideoTracks()) {
      _videoSender = await pc.addTrack(track, stream);
    }

    if (_videoSender == null) {
      await _closeScreenSharePeerConnection(
        clearRemoteStream: false,
        stopLocalStream: true,
      );
      throw Exception('No video track available for screen capture');
    }

    if (_autoQuality) {
      _qualityTier = 0;
      await _applyQualityTier();
      _startAdaptiveQuality();
    } else {
      await _applyEncoderParams(
        bitrateKbps: _baseBitrateKbps,
        fps: fps,
        scaleDown: 1.0,
      );
    }

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _sendScreenShareOffer(offer);
  }

  Future<rtc.MediaStream> _getDisplayMediaStream({
    required String sourceId,
    required int fps,
  }) async {
    Object? lastError;
    rtc.MediaStream? stream;

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
        stream = await rtc.navigator.mediaDevices.getDisplayMedia(attempt);
        break;
      } catch (error) {
        lastError = error;
        _log.warning('Screen share getDisplayMedia attempt failed: $error');
      }
    }

    if (stream == null) {
      throw Exception('Unable to getDisplayMedia after retries: $lastError');
    }

    return stream;
  }

  Future<rtc.RTCPeerConnection> _createScreenSharePeerConnection() async {
    final pc = await rtc.createPeerConnection(_toFlutterRtcConfiguration());
    _screenSharePeerConnection = pc;

    pc.onIceCandidate = (candidate) {
      final candidateValue = candidate.candidate;
      if (candidateValue == null || candidateValue.isEmpty) {
        return;
      }
      unawaited(_sendScreenShareIce(candidate));
    };

    pc.onTrack = (event) {
      final streams = event.streams;
      if (streams.isEmpty) {
        return;
      }
      _remoteStream = streams.first;
      if (!_onRemoteStreamController.isClosed) {
        _onRemoteStreamController.add(streams.first);
      }
    };

    return pc;
  }

  Future<void> stopScreenCapture() async {
    stopAdaptiveQuality();
    await _closeScreenSharePeerConnection(
      clearRemoteStream: false,
      stopLocalStream: true,
    );
  }

  Future<void> sendRenegotiationIce(RTCIceCandidate candidate) {
    return rust_webrtc.sendRenegotiationIce(
      connectionId: _connectionId,
      candidate: rust_webrtc.IceCandidateDto(
        candidate: candidate.candidate,
        sdpMid: candidate.sdpMid,
        sdpMlineIndex: candidate.sdpMLineIndex,
      ),
    );
  }

  Future<void> sendSessionClosed({required String id, String? reason}) {
    return rust_webrtc.sendSessionClosed(
      connectionId: _connectionId,
      id: id,
      reason: reason,
    );
  }

  Future<void> sendPing(String ts) {
    return rust_webrtc.sendPing(connectionId: _connectionId, ts: ts);
  }

  Future<void> sendFileTransferPrompt() {
    return rust_webrtc.sendFileTransferPrompt(connectionId: _connectionId);
  }

  Future<void> sendFileMessage(String message) {
    return rust_webrtc.sendFileMessage(
      connectionId: _connectionId,
      message: message,
    );
  }

  Future<void> sendFileChunk(List<int> bytes) {
    return rust_webrtc.sendFileChunk(connectionId: _connectionId, bytes: bytes);
  }

  Future<void> createFileTransferChannel() async {
    // Rust side creates file_transfer channel during offer creation.
  }

  void _startEventPolling() {
    _eventPollTimer?.cancel();
    _eventPollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      unawaited(_drainRustEvents());
    });
  }

  Future<void> _drainRustEvents() async {
    if (_eventPollInFlight) return;
    _eventPollInFlight = true;
    try {
      final events = await rust_webrtc.drainEvents(connectionId: _connectionId);
      if (events.isEmpty) {
        _lastFileBufferedAmount = (await rust_webrtc.getFileBufferedAmount(
          connectionId: _connectionId,
        )).toInt();
        return;
      }

      for (final event in events) {
        event.when(
          connectionStateChanged: (state) {
            final mapped = _mapPeerConnectionState(state);
            _lastConnectionState = mapped;
            _onStateChangeController.add(mapped);
          },
          dataChannelStateChanged: (label, state) {
            if (label == 'file_transfer') {
              final mappedState = _mapDataChannelState(state);
              _lastFileChannelState = mappedState;
              _onFileChannelStateController.add(mappedState);
            }
          },
          localIceCandidate: (candidate) {
            _onIceCandidateController.add(
              RTCIceCandidate(
                candidate.candidate,
                candidate.sdpMid,
                candidate.sdpMlineIndex,
              ),
            );
          },
          renegotiationOffer: (description) {
            _onRenegotiationOfferController.add(
              RTCSessionDescription(description.sdp, description.kind),
            );
          },
          renegotiationAnswer: (description) {
            _onRenegotiationAnswerController.add(
              RTCSessionDescription(description.sdp, description.kind),
            );
          },
          renegotiationIce: (candidate) {
            _onRenegotiationIceController.add(
              RTCIceCandidate(
                candidate.candidate,
                candidate.sdpMid,
                candidate.sdpMlineIndex,
              ),
            );
          },
          videoFrame: (data, width, height) {},
          fileTransferRequested: () {
            _onFileTransferRequestedController.add(true);
          },
          sessionClosed: (id, reason) {
            if (id != null) {
              unawaited(
                rust_webrtc.sendSessionClosedAck(
                  connectionId: _connectionId,
                  id: id,
                ),
              );
            }
            _onPeerSessionClosedController.add(true);
          },
          sessionClosedAck: (id) {
            _onSessionClosedAckController.add(id);
          },
          ping: (ts) {
            unawaited(
              rust_webrtc.sendPong(connectionId: _connectionId, ts: ts),
            );
          },
          pong: (ts) {
            _onPongController.add(ts);
          },
          controlMessage: (message) {
            unawaited(_handleQueuedControlMessage(message));
          },
          fileMessage: (message) {
            _onFileMessageController.add(message);
          },
          fileChunk: (bytes) {
            _onFileChunkController.add(bytes);
          },
          fileBufferedAmountLow: () {
            final callback = _onFileBufferedAmountLow;
            if (callback != null) callback();
          },
        );
      }

      _lastFileBufferedAmount = (await rust_webrtc.getFileBufferedAmount(
        connectionId: _connectionId,
      )).toInt();
    } catch (error) {
      _log.fine('Event drain error (session may be closing): $error');
    } finally {
      _eventPollInFlight = false;
    }
  }

  Future<void> _handleQueuedControlMessage(String message) async {
    final completer = Completer<bool>();
    _screenControlChain = _screenControlChain.catchError((_) {}).then((
      _,
    ) async {
      try {
        completer.complete(await _handleScreenShareControlMessage(message));
      } catch (error) {
        _log.warning('Screen-share control handling failed: $error');
        completer.complete(false);
      }
    });

    final handled = await completer.future;
    if (!handled && !_onMessageController.isClosed) {
      _onMessageController.add(message);
    }
  }

  Future<bool> _handleScreenShareControlMessage(String message) async {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(message) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }

    switch (decoded['type']) {
      case _screenShareOfferType:
        final data = (decoded['data'] as Map?)?.cast<String, dynamic>();
        if (data == null) return false;
        await _handleIncomingScreenShareOffer(data);
        return true;
      case _screenShareAnswerType:
        final data = (decoded['data'] as Map?)?.cast<String, dynamic>();
        if (data == null) return false;
        await _handleIncomingScreenShareAnswer(data);
        return true;
      case _screenShareIceType:
        final data = (decoded['data'] as Map?)?.cast<String, dynamic>();
        if (data == null) return false;
        await _handleIncomingScreenShareIce(data);
        return true;
      case _screenShareStoppedType:
        await _handleRemoteScreenShareStopped();
        return true;
      default:
        return false;
    }
  }

  Future<void> _handleIncomingScreenShareOffer(
    Map<String, dynamic> data,
  ) async {
    await _closeScreenSharePeerConnection(
      clearRemoteStream: false,
      stopLocalStream: true,
    );

    final pc = await _createScreenSharePeerConnection();
    await pc.setRemoteDescription(
      rtc.RTCSessionDescription(data['sdp'] as String, data['type'] as String),
    );

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await _sendScreenShareAnswer(answer);
  }

  Future<void> _handleIncomingScreenShareAnswer(
    Map<String, dynamic> data,
  ) async {
    final pc = _screenSharePeerConnection;
    if (pc == null) {
      return;
    }

    await pc.setRemoteDescription(
      rtc.RTCSessionDescription(data['sdp'] as String, data['type'] as String),
    );
  }

  Future<void> _handleIncomingScreenShareIce(Map<String, dynamic> data) async {
    final pc = _screenSharePeerConnection;
    if (pc == null) {
      return;
    }

    await pc.addCandidate(
      rtc.RTCIceCandidate(
        data['candidate'] as String,
        data['sdpMid'] as String?,
        (data['sdpMLineIndex'] as num?)?.toInt(),
      ),
    );
  }

  Future<void> _handleRemoteScreenShareStopped() async {
    await _closeScreenSharePeerConnection(
      clearRemoteStream: true,
      stopLocalStream: false,
    );
    if (!_onScreenShareStoppedController.isClosed) {
      _onScreenShareStoppedController.add(true);
    }
  }

  Future<void> _sendScreenShareOffer(rtc.RTCSessionDescription description) {
    return sendControlMessage(
      jsonEncode({
        'type': _screenShareOfferType,
        'data': {'sdp': description.sdp ?? '', 'type': description.type},
      }),
    );
  }

  Future<void> _sendScreenShareAnswer(rtc.RTCSessionDescription description) {
    return sendControlMessage(
      jsonEncode({
        'type': _screenShareAnswerType,
        'data': {'sdp': description.sdp ?? '', 'type': description.type},
      }),
    );
  }

  Future<void> _sendScreenShareIce(rtc.RTCIceCandidate candidate) {
    return sendControlMessage(
      jsonEncode({
        'type': _screenShareIceType,
        'data': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      }),
    );
  }

  Future<void> _closeScreenSharePeerConnection({
    required bool clearRemoteStream,
    required bool stopLocalStream,
  }) async {
    final pc = _screenSharePeerConnection;
    _screenSharePeerConnection = null;
    _videoSender = null;
    if (pc != null) {
      await pc.close();
    }

    if (stopLocalStream && _localScreenStream != null) {
      for (final track in _localScreenStream!.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      _localScreenStream = null;
    }

    if (stopLocalStream) {
      _currentScreenShareStatus = null;
      _currentBitrateKbps = _baseBitrateKbps;
      _currentFps = _baseFps;
      _currentScaleDown = 1.0;
    }

    if (clearRemoteStream) {
      _remoteStream = null;
    }
  }

  Future<void> _applyEncoderParams({
    required int bitrateKbps,
    required int fps,
    required double scaleDown,
  }) async {
    final sender = _videoSender;
    if (sender == null) {
      return;
    }

    try {
      final params = rtc.RTCRtpParameters(
        encodings: [
          rtc.RTCRtpEncoding(
            active: true,
            maxBitrate: bitrateKbps * _KBPS_TO_BPS_MULTIPLIER,
            maxFramerate: fps,
            scaleResolutionDownBy: scaleDown,
          ),
        ],
      );
      await sender.setParameters(params);
      _currentBitrateKbps = bitrateKbps;
      _currentFps = fps;
      _currentScaleDown = scaleDown;
      _emitScreenShareStatus();
      _log.info(
        'Screen-share encoder params set: '
        '${bitrateKbps}kbps, ${fps}fps, scale x$scaleDown',
      );
    } catch (error) {
      _log.warning('Screen-share setParameters failed: $error');
    }
  }

  void _startAdaptiveQuality() {
    _qualityTier = 0;
    _consecutiveGoodPolls = 0;
    _consecutiveBadPolls = 0;
    _adaptiveQualityTimer?.cancel();
    _adaptiveQualityTimer = Timer.periodic(
      const Duration(seconds: _ADAPTIVE_QUALITY_POLL_INTERVAL_SECONDS),
      (_) => _checkAndAdaptQuality(),
    );
  }

  void stopAdaptiveQuality() {
    _adaptiveQualityTimer?.cancel();
    _adaptiveQualityTimer = null;
  }

  Future<void> _checkAndAdaptQuality() async {
    final pc = _screenSharePeerConnection;
    final sender = _videoSender;
    if (pc == null || sender == null) {
      return;
    }

    try {
      final stats = await pc.getStats(null);
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

      _emitScreenShareStatus(stats: stats);

      if (fractionLost < 0) {
        return;
      }

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
    } catch (error) {
      _log.warning('Screen-share adaptive quality stats check failed: $error');
    }
  }

  Future<void> _applyQualityTier() async {
    late int kbps;
    late int fps;
    late double scale;

    switch (_qualityTier) {
      case 0:
        kbps = _baseBitrateKbps;
        fps = _baseFps;
        scale = 1.0;
        break;
      case 1:
        kbps = (_baseBitrateKbps * _TIER1_BITRATE_FACTOR).round().clamp(
          _MIN_BITRATE_KBPS,
          _baseBitrateKbps,
        );
        fps = (_baseFps * _TIER1_FPS_FACTOR).round().clamp(
          _MIN_FPS_MID_QUALITY,
          _MAX_FPS,
        );
        scale = _TIER1_SCALE;
        break;
      case 2:
        kbps = (_baseBitrateKbps * _TIER2_BITRATE_FACTOR).round().clamp(
          _MIN_BITRATE_KBPS,
          _baseBitrateKbps,
        );
        fps = (_baseFps * _TIER2_FPS_FACTOR).round().clamp(
          _MIN_FPS_LOW_QUALITY,
          20,
        );
        scale = _TIER2_SCALE;
        break;
      default:
        kbps = _TIER3_BITRATE_KBPS;
        fps = _TIER3_FPS;
        scale = _TIER3_SCALE;
        break;
    }

    await _applyEncoderParams(bitrateKbps: kbps, fps: fps, scaleDown: scale);
  }

  void _emitScreenShareStatus({List<rtc.StatsReport>? stats}) {
    final status = _buildScreenShareQualityStatus(stats: stats);
    if (status == null) {
      return;
    }

    _currentScreenShareStatus = status;
    if (!_onScreenShareStatusController.isClosed) {
      _onScreenShareStatusController.add(status);
    }
  }

  ScreenShareQualityStatus? _buildScreenShareQualityStatus({
    List<rtc.StatsReport>? stats,
  }) {
    final encodedDimensionsFromStats = _readEncodedDimensionsFromStats(stats);
    final sourceDimensions =
        _readSourceDimensionsFromStats(stats) ??
        _readLocalScreenDimensions() ??
        encodedDimensionsFromStats ??
        (_currentScreenShareStatus == null
            ? null
            : (
                _currentScreenShareStatus!.width,
                _currentScreenShareStatus!.height,
              ));
    if (sourceDimensions == null) {
      return null;
    }

    final encodedDimensions =
        encodedDimensionsFromStats ??
        _scaleDimensions(
          width: sourceDimensions.$1,
          height: sourceDimensions.$2,
          scaleDown: _currentScaleDown,
        );
    final fps = _readFramesPerSecond(stats) ?? _currentFps;

    return ScreenShareQualityStatus(
      width: encodedDimensions.$1,
      height: encodedDimensions.$2,
      fps: fps,
      bitrateKbps: _currentBitrateKbps,
      autoQuality: _autoQuality,
      qualityLabel: _formatQualityLabel(
        width: encodedDimensions.$1,
        height: encodedDimensions.$2,
      ),
    );
  }

  (int, int)? _readLocalScreenDimensions() {
    final stream = _localScreenStream;
    if (stream == null) {
      return null;
    }

    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) {
      return null;
    }

    final settings = videoTracks.first.getSettings();
    final width = _readPositiveInt(settings['width']);
    final height = _readPositiveInt(settings['height']);
    if (width == null || height == null) {
      return null;
    }

    return (width, height);
  }

  (int, int)? _readSourceDimensionsFromStats(List<rtc.StatsReport>? stats) {
    return _readDimensionsFromStats(
      stats: stats,
      reportTypes: const {'track', 'media-source'},
    );
  }

  (int, int)? _readEncodedDimensionsFromStats(List<rtc.StatsReport>? stats) {
    return _readDimensionsFromStats(
      stats: stats,
      reportTypes: const {'outbound-rtp'},
    );
  }

  (int, int)? _readDimensionsFromStats({
    required List<rtc.StatsReport>? stats,
    required Set<String> reportTypes,
  }) {
    if (stats == null) {
      return null;
    }

    for (final report in stats) {
      if (!reportTypes.contains(report.type)) {
        continue;
      }

      final values = report.values;
      if (!_isVideoStatsReport(reportType: report.type, values: values)) {
        continue;
      }

      final width = _readPositiveInt(
        values['frameWidth'] ?? values['frame-width'],
      );
      final height = _readPositiveInt(
        values['frameHeight'] ?? values['frame-height'],
      );
      if (width != null && height != null) {
        return (width, height);
      }
    }

    return null;
  }

  int? _readFramesPerSecond(List<rtc.StatsReport>? stats) {
    return _readFramesPerSecondFromStats(
          stats: stats,
          reportTypes: const {'outbound-rtp'},
        ) ??
        _readFramesPerSecondFromStats(
          stats: stats,
          reportTypes: const {'track', 'media-source'},
        );
  }

  int? _readFramesPerSecondFromStats({
    required List<rtc.StatsReport>? stats,
    required Set<String> reportTypes,
  }) {
    if (stats == null) {
      return null;
    }

    for (final report in stats) {
      if (!reportTypes.contains(report.type)) {
        continue;
      }

      final values = report.values;
      if (!_isVideoStatsReport(reportType: report.type, values: values)) {
        continue;
      }

      final fps = _readPositiveInt(
        values['framesPerSecond'] ?? values['frames-per-second'],
      );
      if (fps != null) {
        return fps;
      }
    }

    return null;
  }

  bool _isVideoStatsReport({
    required String reportType,
    required Map<dynamic, dynamic> values,
  }) {
    final mediaType = values['mediaType'];
    final kind = values['kind'];
    if (mediaType == 'video' || kind == 'video') {
      return true;
    }

    if (reportType == 'outbound-rtp') {
      return false;
    }

    return values.containsKey('frameWidth') ||
        values.containsKey('frame-width') ||
        values.containsKey('frameHeight') ||
        values.containsKey('frame-height');
  }

  (int, int) _scaleDimensions({
    required int width,
    required int height,
    required double scaleDown,
  }) {
    if (scaleDown <= 1.0) {
      return (width, height);
    }

    return (
      math.max(1, (width / scaleDown).round()),
      math.max(1, (height / scaleDown).round()),
    );
  }

  int? _readPositiveInt(Object? value) {
    final parsed = switch (value) {
      int value => value,
      num value => value.round(),
      String value =>
        int.tryParse(value.trim()) ?? num.tryParse(value.trim())?.round(),
      _ => null,
    };
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  String _formatQualityLabel({required int width, required int height}) {
    return '${math.min(width, height)}p';
  }

  RTCPeerConnectionState _mapPeerConnectionState(String state) {
    switch (state.toLowerCase()) {
      case 'connecting':
        return RTCPeerConnectionState.RTCPeerConnectionStateConnecting;
      case 'connected':
        return RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      case 'disconnected':
        return RTCPeerConnectionState.RTCPeerConnectionStateDisconnected;
      case 'failed':
        return RTCPeerConnectionState.RTCPeerConnectionStateFailed;
      case 'closed':
        return RTCPeerConnectionState.RTCPeerConnectionStateClosed;
      default:
        return RTCPeerConnectionState.RTCPeerConnectionStateNew;
    }
  }

  RTCDataChannelState _mapDataChannelState(String state) {
    switch (state.toLowerCase()) {
      case 'open':
        return RTCDataChannelState.RTCDataChannelStateOpen;
      case 'closing':
        return RTCDataChannelState.RTCDataChannelStateClosing;
      case 'closed':
        return RTCDataChannelState.RTCDataChannelStateClosed;
      default:
        return RTCDataChannelState.RTCDataChannelStateConnecting;
    }
  }

  Future<void> dispose() async {
    _eventPollTimer?.cancel();
    _eventPollTimer = null;

    stopAdaptiveQuality();
    await _closeScreenSharePeerConnection(
      clearRemoteStream: true,
      stopLocalStream: true,
    );
    await rust_webrtc.closeSession(connectionId: _connectionId);

    await _onScreenShareStatusController.close();
    await _onScreenShareStoppedController.close();
    await _onRemoteMediaStateController.close();
    await _onMessageController.close();
    await _onFileChunkController.close();
    await _onFileMessageController.close();
    await _onRenegotiationOfferController.close();
    await _onRenegotiationAnswerController.close();
    await _onRenegotiationIceController.close();
    await _onPeerSessionClosedController.close();
    await _onSessionClosedAckController.close();
    await _onPongController.close();
    await _onFileTransferRequestedController.close();
    await _onFileChannelStateController.close();
    await _onStateChangeController.close();
    await _onIceCandidateController.close();
    await _onRemoteStreamController.close();
  }
}
