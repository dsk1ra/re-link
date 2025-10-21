import 'models.dart';

abstract class SignalingBackend {
  Future<RegisterResponse> register({required String deviceLabel});
  Future<HeartbeatResponse?> heartbeat();
  Future<CreateRoomResponse> roomCreate();
  Future<JoinRoomResponse> roomJoin({required String roomId, required String password});
  Future<(String status, int? ttlSeconds)> roomStatus(String roomId);
  Future<void> dispose();
  bool get isRegistered;
  String? get clientId;
  String? get sessionToken;
  String? get displayName;
}
