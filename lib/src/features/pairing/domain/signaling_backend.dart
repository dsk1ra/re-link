import 'models.dart';

abstract class SignalingBackend {
  Future<RegisterResponse> register({required String deviceLabel});
  Future<HeartbeatResponse?> heartbeat();
  Future<void> dispose();
  bool get isRegistered;
  String? get clientId;
  String? get sessionToken;
  String? get displayName;
}
