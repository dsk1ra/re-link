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
