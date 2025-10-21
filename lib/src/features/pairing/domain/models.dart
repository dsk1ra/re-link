class RegisterResponse {
  final String clientId; // UUID
  final String sessionToken;
  final int heartbeatIntervalSecs;
  final String displayName;

  RegisterResponse({
    required this.clientId,
    required this.sessionToken,
    required this.heartbeatIntervalSecs,
    required this.displayName,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) => RegisterResponse(
        clientId: json['client_id'] as String,
        sessionToken: json['session_token'] as String,
        heartbeatIntervalSecs: json['heartbeat_interval_secs'] as int,
        displayName: json['display_name'] as String? ?? 'Client',
      );
}

class HeartbeatResponse {
  final int nextHeartbeatSecs;
  HeartbeatResponse(this.nextHeartbeatSecs);
  factory HeartbeatResponse.fromJson(Map<String, dynamic> json) =>
      HeartbeatResponse(json['next_heartbeat_secs'] as int);
}

class CreateRoomResponse {
  final String roomId; // 32-char hex
  final String password; // 32-char base64
  final String initiatorToken; // 64-char hex
  final BigInt? expiresAtEpochMs; // optional, for countdown
  final int? ttlSeconds; // optional

  CreateRoomResponse({
    required this.roomId,
    required this.password,
    required this.initiatorToken,
    this.expiresAtEpochMs,
    this.ttlSeconds,
  });

  factory CreateRoomResponse.fromJson(Map<String, dynamic> json) => CreateRoomResponse(
        roomId: json['room_id'] as String,
        password: json['password'] as String,
        initiatorToken: json['initiator_token'] as String,
        expiresAtEpochMs: json['expires_at_epoch_ms'] == null
            ? null
            : BigInt.parse(json['expires_at_epoch_ms'].toString()),
        ttlSeconds: (json['ttl_seconds'] as num?)?.toInt(),
      );
}

class JoinRoomResponse {
  final String initiatorToken; // 64-char hex
  final String receiverToken; // 64-char hex

  JoinRoomResponse({required this.initiatorToken, required this.receiverToken});

  factory JoinRoomResponse.fromJson(Map<String, dynamic> json) => JoinRoomResponse(
        initiatorToken: json['initiator_token'] as String,
        receiverToken: json['receiver_token'] as String,
      );
}
