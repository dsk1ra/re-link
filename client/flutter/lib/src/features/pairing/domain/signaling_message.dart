import 'dart:convert';

class SignalingMessage {
  SignalingMessage({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;

  String toJsonString() {
    return jsonEncode({'type': type, 'data': data});
  }

  factory SignalingMessage.fromJsonString(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return SignalingMessage(
      type: decoded['type'] as String,
      data:
          (decoded['data'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
    );
  }
}
