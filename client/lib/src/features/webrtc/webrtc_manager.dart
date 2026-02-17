import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

/// Manages WebRTC peer connection with minimal signaling
class WebRTCManager {
  static final Logger _log = Logger('WebRTCManager');
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _controlChannel;
  RTCDataChannel? _fileTransferChannel;

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
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:stun3.l.google.com:19302'},
        {'urls': 'stun:stun4.l.google.com:19302'},
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

    _log.info('WebRTC: Initialization complete.');
  }

  void _setupIncomingChannel(RTCDataChannel channel) {
    _log.info('WebRTC: Received DataChannel: ${channel.label}');
    if (channel.label == 'control' || channel.label == 'data') {
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

    // Negotiate if needed (WebRTC usually handles this if negotiationneeded event fires)
    // However, if we are the Offerer (Initiator), we might need to create a new Offer.
    // Ideally, we rely on `onRenegotiationNeeded`.
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
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_fileTransferChannel?.state ==
          RTCDataChannelState.RTCDataChannelOpen) {
        if (!pollCompleter.isCompleted) {
          pollCompleter.complete();
        }
        timer.cancel();
      }
    });

    await Future.any([waitForOpen, pollCompleter.future]).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('Timeout waiting for file transfer channel to open');
      },
    );
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

  Future<void> dispose() async {
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
