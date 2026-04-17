import 'dart:async';

import 'package:application/src/rust/api/share.dart' as rust_share;
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

  WebRTCManager({
    required String connectionId,
    List<Map<String, dynamic>>? iceServers,
  }) : _connectionId = connectionId,
       _iceServers = iceServers;

  final String _connectionId;
  final List<Map<String, dynamic>>? _iceServers;

  String get connectionId => _connectionId;

  final _onQualityChangeController = StreamController<String>.broadcast();
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
  final _onScreenShareStoppedController = StreamController<bool>.broadcast();
  final _onFileTransferRequestedController = StreamController<bool>.broadcast();
  final _onFileChannelStateController =
      StreamController<RTCDataChannelState>.broadcast();
  final _onStateChangeController =
      StreamController<RTCPeerConnectionState>.broadcast();
  final _onIceCandidateController =
      StreamController<RTCIceCandidate>.broadcast();

  Stream<String> get onMessage => _onMessageController.stream;
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
  Stream<bool> get onScreenShareStopped =>
      _onScreenShareStoppedController.stream;
  Stream<bool> get onFileTransferRequested =>
      _onFileTransferRequestedController.stream;
  Stream<RTCDataChannelState> get onFileChannelState =>
      _onFileChannelStateController.stream;
  Stream<RTCPeerConnectionState> get onStateChange =>
      _onStateChangeController.stream;
  Stream<RTCIceCandidate> get onIceCandidate =>
      _onIceCandidateController.stream;
  Stream<String> get onQualityChange => _onQualityChangeController.stream;

  RTCPeerConnectionState? _lastConnectionState;
  RTCDataChannelState? _lastFileChannelState;
  int _lastFileBufferedAmount = 0;
  Timer? _eventPollTimer;
  bool _eventPollInFlight = false;
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

  Future<RTCSessionDescription> createRenegotiationOffer() async {
    return createOffer();
  }

  Future<void> startScreenCapture({
    required String sourceId,
    required int fps,
    int? bitrateKbps,
  }) async {
    rust_share.init();
    rust_share.startShare(
      connectionId: _connectionId,
      sourceId: sourceId,
      config: rust_share.ShareConfig(
        fps: fps,
        bitratePreset: _bitratePresetFor(bitrateKbps),
      ),
    );
    _onQualityChangeController.add(
      'Rust-managed WebRTC active. Screen source $sourceId requested at ${fps}fps.',
    );
  }

  Future<void> stopScreenCapture() async {
    rust_share.stopShare(connectionId: _connectionId);
    _onQualityChangeController.add('Screen sharing stopped.');
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

  Future<void> sendScreenShareStopped() {
    return rust_webrtc.sendScreenShareStopped(connectionId: _connectionId);
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

  Future<List<rust_share.SourceDescriptor>> listShareSources() async {
    rust_share.init();
    return rust_share.listShareSources();
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
          screenShareStopped: () {
            _onScreenShareStoppedController.add(true);
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
            _onMessageController.add(message);
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

  rust_share.BitratePreset _bitratePresetFor(int? bitrateKbps) {
    if (bitrateKbps == null || bitrateKbps >= 4000) {
      return rust_share.BitratePreset.high;
    }
    if (bitrateKbps >= 1000) {
      return rust_share.BitratePreset.medium;
    }
    return rust_share.BitratePreset.low;
  }

  Future<void> dispose() async {
    _eventPollTimer?.cancel();
    _eventPollTimer = null;

    await rust_webrtc.closeSession(connectionId: _connectionId);

    await _onQualityChangeController.close();
    await _onMessageController.close();
    await _onFileChunkController.close();
    await _onFileMessageController.close();
    await _onRenegotiationOfferController.close();
    await _onRenegotiationAnswerController.close();
    await _onRenegotiationIceController.close();
    await _onPeerSessionClosedController.close();
    await _onSessionClosedAckController.close();
    await _onPongController.close();
    await _onScreenShareStoppedController.close();
    await _onFileTransferRequestedController.close();
    await _onFileChannelStateController.close();
    await _onStateChangeController.close();
    await _onIceCandidateController.close();
  }
}
