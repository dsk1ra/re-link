import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:application/src/presentation/widgets/raw_video_frame_view.dart';
import 'package:application/src/rust/api/audio.dart' as rust_audio;
import 'package:application/src/rust/api/desktop_audio.dart' as rust_desktop_audio;
import 'package:application/src/rust/api/input_inject.dart' as rust_input;
import 'package:application/src/rust/api/screen_capture.dart'
    as rust_screen_capture;
import 'package:application/src/rust/api/video_ring.dart' as rust_video_ring;
import 'package:application/src/rust/api/webrtc.dart' as rust_webrtc;
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

class WebRTCManager {
  static final Logger _log = Logger('WebRTCManager');

  static const String _screenShareStoppedType = 'screen_share_stopped';

  WebRTCManager({
    required String connectionId,
    List<Map<String, dynamic>>? iceServers,
  }) : _connectionId = connectionId,
       _iceServers = iceServers;

  final String _connectionId;
  final List<Map<String, dynamic>>? _iceServers;

  String get connectionId => _connectionId;

  final _onScreenShareStoppedController = StreamController<bool>.broadcast();
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
  final _onVideoFrameController = StreamController<VideoFrameData>.broadcast();
  final _onVideoFrameSizeController =
      StreamController<({int width, int height})>.broadcast();

  Stream<String> get onMessage => _onMessageController.stream;
  Stream<bool> get onScreenShareStopped =>
      _onScreenShareStoppedController.stream;
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
  Stream<VideoFrameData> get onVideoFrame => _onVideoFrameController.stream;

  /// Frame dimensions only — no ring-slot ownership attached. Listen to this
  /// for "is video present / what size" gates; `onVideoFrame` must have
  /// exactly one consumer (the rendering view), because a broadcast frame
  /// delivered to a metadata-only listener would leak its ring slot.
  Stream<({int width, int height})> get onVideoFrameSize =>
      _onVideoFrameSizeController.stream;

  RTCPeerConnectionState? _lastConnectionState;
  RTCDataChannelState? _lastFileChannelState;
  int _lastFileBufferedAmount = 0;
  StreamSubscription<rust_webrtc.WebRtcEvent>? _eventStreamSub;
  StreamSubscription<rust_webrtc.RawVideoFrame>? _videoStreamSub;
  Function()? _onFileBufferedAmountLow;

  bool get isConnected =>
      _lastConnectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  RTCDataChannelState? get fileChannelState => _lastFileChannelState;

  int? get fileChannelBufferedAmount => _lastFileBufferedAmount;

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

    _subscribeStreams();
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

  Future<void> requestIceRestart() async {
    _log.info('Requesting ICE restart');
    final offer = await rust_webrtc.createRestartOffer(
      connectionId: _connectionId,
    );
    final desc = RTCSessionDescription(offer.sdp, offer.kind);
    await sendRenegotiationOffer(desc);
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

  // ─── Remote input (viewer → host) ────────────────────────────────────────
  // nx/ny are normalized [0,1] within the shared source's content. The host
  // maps them to real screen coordinates and scopes/injects them - see
  // input_inject.rs. Fire-and-forget: dropped frames just miss one move.

  Future<void> sendInputMouseMove(double nx, double ny) {
    return sendMessage(jsonEncode({'type': 'input_mouse_move', 'nx': nx, 'ny': ny}));
  }

  Future<void> sendInputMouseButton(
    double nx,
    double ny,
    String button,
    bool pressed,
  ) {
    return sendMessage(jsonEncode({
      'type': 'input_mouse_button',
      'nx': nx,
      'ny': ny,
      'button': button,
      'pressed': pressed,
    }));
  }

  Future<void> sendInputMouseScroll(double nx, double ny, double deltaY) {
    return sendMessage(jsonEncode({
      'type': 'input_mouse_scroll',
      'nx': nx,
      'ny': ny,
      'deltaY': deltaY,
    }));
  }

  Future<void> sendInputKey({int? unicode, String? named, required bool pressed}) {
    return sendMessage(jsonEncode({
      'type': 'input_key',
      if (unicode != null) 'unicode': unicode,
      if (named != null) 'named': named,
      'pressed': pressed,
    }));
  }

  /// Host-side consent toggle - must be enabled before the peer's
  /// input_* messages are acted on. Local call, doesn't cross the network.
  Future<void> setRemoteControlAllowed(bool allowed) {
    return rust_input.setRemoteControlAllowed(
      connectionId: _connectionId,
      allowed: allowed,
    );
  }

  List<rust_screen_capture.CaptureSourceDto> listCaptureSources() {
    return rust_screen_capture.listCaptureSources();
  }

  Future<void> startScreenCapture({
    required String sourceId,
    required int fps,
    int targetBitrateKbps = 2000,
    bool localPreview = false,
  }) {
    return rust_screen_capture.startCapture(
      connectionId: _connectionId,
      sourceId: sourceId,
      config: rust_screen_capture.CaptureConfigDto(
        fps: fps,
        targetBitrateKbps: targetBitrateKbps,
      ),
      localPreview: localPreview,
    );
  }

  Future<void> stopScreenCapture() {
    return rust_screen_capture.stopCapture(connectionId: _connectionId);
  }

  bool get isCaptureActive {
    return rust_screen_capture.isCaptureActive(connectionId: _connectionId);
  }

  // ─── Desktop audio (Linux/PipeWire loopback, alongside screen capture) ────

  Future<void> startDesktopAudioCapture() {
    return rust_desktop_audio.startDesktopAudioCapture(
      connectionId: _connectionId,
    );
  }

  Future<void> stopDesktopAudioCapture() {
    return rust_desktop_audio.stopDesktopAudioCapture(
      connectionId: _connectionId,
    );
  }

  bool get isDesktopAudioCaptureActive {
    return rust_desktop_audio.isDesktopAudioCaptureActive(
      connectionId: _connectionId,
    );
  }

  Future<List<rust_audio.AudioSourceDto>> listAudioSources() {
    return rust_audio.listAudioSources();
  }

  Future<void> startAudioCapture({String? sourceId}) {
    return rust_audio.startAudioCapture(
      connectionId: _connectionId,
      sourceId: sourceId,
    );
  }

  Future<void> setAudioMuted(bool muted) {
    return rust_audio.setAudioMuted(connectionId: _connectionId, muted: muted);
  }

  Future<void> setAudioSource(String? sourceId) {
    return rust_audio.setAudioSource(
      connectionId: _connectionId,
      sourceId: sourceId,
    );
  }

  Future<void> stopAudioCapture() {
    return rust_audio.stopAudioCapture(connectionId: _connectionId);
  }

  bool get isAudioCaptureActive {
    return rust_audio.isAudioCaptureActive(connectionId: _connectionId);
  }

  bool get isAudioMuted {
    return rust_audio.isAudioMuted(connectionId: _connectionId);
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
    await rust_webrtc.waitForFileChannelReady(connectionId: _connectionId);
  }

  void _subscribeStreams() {
    _eventStreamSub = rust_webrtc
        .subscribeEventStream(connectionId: _connectionId)
        .listen(_handleEvent, onError: (e) {
      _log.fine('Event stream error (session may be closing): $e');
    });

    _videoStreamSub = rust_webrtc
        .subscribeVideoStream(connectionId: _connectionId)
        .listen((frame) {
      final slot = frame.slot;
      if (_onVideoFrameController.isClosed) {
        rust_video_ring.releaseVideoFrame(slot: slot);
        return;
      }
      if (!_onVideoFrameSizeController.isClosed) {
        _onVideoFrameSizeController.add((
          width: frame.width,
          height: frame.height,
        ));
      }
      // Both decode paths (GStreamer NVDEC and the openh264 fallback) render
      // pixels through VIDEO_TEXTURE and emit a `len==0` sentinel here so the
      // page can flip its "remote video present" gate and learn the source
      // frame dimensions for aspect-ratio-correct rendering. No FFI deref
      // or slot release needed — the sentinel carries no pixel data.
      if (frame.len == 0) {
        _onVideoFrameController.add(VideoFrameData(
          rgba: Uint8List(0),
          width: frame.width,
          height: frame.height,
          release: () {},
        ));
        return;
      }
      // A broadcast controller silently drops events when nobody listens,
      // which would leak the ring slot forever (the ring is a process-wide
      // static — leaked slots never come back). Release it here instead.
      if (!_onVideoFrameController.hasListener) {
        rust_video_ring.releaseVideoFrame(slot: slot);
        return;
      }
      // Real frames: zero-copy view onto a Rust ring slot. The slot is
      // reserved until releaseVideoFrame(slot) is called; the view must
      // NOT outlive that call. The downstream consumer
      // (RawVideoFrameView) invokes release once it's done with the
      // bytes — typically after ui.decodeImageFromPixels has copied them
      // into a Skia image.
      final pointer = ffi.Pointer<ffi.Uint8>.fromAddress(frame.addr);
      final view = pointer.asTypedList(frame.len);
      _onVideoFrameController.add(
        VideoFrameData(
          rgba: view,
          width: frame.width,
          height: frame.height,
          release: () => rust_video_ring.releaseVideoFrame(slot: slot),
        ),
      );
    });
  }

  void _handleEvent(rust_webrtc.WebRtcEvent event) {
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
      videoFrame: (data, width, height) {
        // Legacy variant. The ring-buffer path replaced this — Rust no
        // longer produces VideoFrame events. If one still arrives from a
        // stale buffered event, just drop it.
      },
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
        _handleControlMessage(message);
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

  void _handleControlMessage(String message) {
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      if (decoded['type'] == _screenShareStoppedType) {
        if (!_onScreenShareStoppedController.isClosed) {
          _onScreenShareStoppedController.add(true);
        }
        return;
      }
    } catch (_) {}

    if (!_onMessageController.isClosed) {
      _onMessageController.add(message);
    }
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
    await _eventStreamSub?.cancel();
    _eventStreamSub = null;
    await _videoStreamSub?.cancel();
    _videoStreamSub = null;

    await rust_webrtc.closeSession(connectionId: _connectionId);

    await _onScreenShareStoppedController.close();
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
    await _onVideoFrameController.close();
    await _onVideoFrameSizeController.close();
  }
}
