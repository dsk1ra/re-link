import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Manages WebRTC peer connection with minimal signaling
class WebRTCManager {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  
  final _onMessageController = StreamController<String>.broadcast();
  final _onStateChangeController = StreamController<RTCPeerConnectionState>.broadcast();
  final _onIceCandidateController = StreamController<RTCIceCandidate>.broadcast();
  
  Stream<String> get onMessage => _onMessageController.stream;
  Stream<RTCPeerConnectionState> get onStateChange => _onStateChangeController.stream;
  Stream<RTCIceCandidate> get onIceCandidate => _onIceCandidateController.stream;
  
  bool get isConnected => 
    _peerConnection?.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
  
  Future<void> initialize() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    
    _peerConnection = await createPeerConnection(config);
    
    _peerConnection!.onConnectionState = (state) {
      // Post to main isolate event loop
      Future(() => _onStateChangeController.add(state));
    };
    
    _peerConnection!.onIceCandidate = (candidate) {
      // Post to main isolate event loop
      Future(() => _onIceCandidateController.add(candidate));
    };
    
    // Add all other state change callbacks with thread safety
    _peerConnection!.onIceConnectionState = (state) {
      Future(() {});
    };
    
    _peerConnection!.onIceGatheringState = (state) {
      Future(() {});
    };
    
    _peerConnection!.onSignalingState = (state) {
      Future(() {});
    };
  }
  
  /// Create offer (initiator side)
  Future<RTCSessionDescription> createOffer() async {
    if (_peerConnection == null) await initialize();
    
    // Create data channel
    final dataChannelInit = RTCDataChannelInit();
    dataChannelInit.ordered = true;
    _dataChannel = await _peerConnection!.createDataChannel('data', dataChannelInit);
    _setupDataChannel(_dataChannel!);
    
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }
  
  /// Handle offer and create answer (responder side)
  Future<RTCSessionDescription> createAnswer(RTCSessionDescription offer) async {
    if (_peerConnection == null) await initialize();
    
    await _peerConnection!.setRemoteDescription(offer);
    
    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      // Post to main isolate event loop
      Future(() => _setupDataChannel(channel));
    };
    
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
  
  /// Send message through data channel
  Future<void> sendMessage(String message) async {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      await _dataChannel!.send(RTCDataChannelMessage(message));
    } else {
      throw Exception('Data channel not open');
    }
  }
  
  void _setupDataChannel(RTCDataChannel channel) {
    channel.onDataChannelState = (state) {
      // Post to main isolate event loop
      Future(() {});
    };
    
    channel.onMessage = (message) {
      // Post to main isolate event loop
      Future(() => _onMessageController.add(message.text));
    };
  }
  
  Future<void> dispose() async {
    await _dataChannel?.close();
    await _peerConnection?.close();
    await _onMessageController.close();
    await _onStateChangeController.close();
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
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'data': data,
  };
  
  String toJsonString() => jsonEncode(toJson());
  
  static SignalingMessage fromJsonString(String json) {
    return SignalingMessage.fromJson(jsonDecode(json));
  }
}
