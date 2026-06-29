import 'dart:async';
import 'dart:io';

enum ServerErrorKind {
  unreachable,
  dnsFailure,
  timeout,
  tlsError,
  serverError,
  blockedByPolicy,
  invalidResponse,
  unknown,
}

class ServerError {
  final ServerErrorKind kind;
  final String userMessage;
  final String? technicalDetail;

  const ServerError({
    required this.kind,
    required this.userMessage,
    this.technicalDetail,
  });

  static ServerError classify(Object error) {
    final message = error.toString();

    if (_isBlockedByPolicy(message)) {
      return const ServerError(
        kind: ServerErrorKind.blockedByPolicy,
        userMessage:
            'Connection blocked by your system. '
            'Check firewall, VPN, or endpoint security settings.',
      );
    }

    if (error is SocketException || _isConnectionRefused(message)) {
      if (_isDnsFailure(message)) {
        return ServerError(
          kind: ServerErrorKind.dnsFailure,
          userMessage:
              'Could not resolve server address. '
              'Check the URL and your internet connection.',
          technicalDetail: message,
        );
      }
      return const ServerError(
        kind: ServerErrorKind.unreachable,
        userMessage:
            'Server is unreachable. '
            'Check that the address is correct and the server is running.',
      );
    }

    if (error is TimeoutException || _isTimeout(message)) {
      return const ServerError(
        kind: ServerErrorKind.timeout,
        userMessage:
            'Server did not respond in time. '
            'It may be overloaded or unreachable.',
      );
    }

    if (error is HandshakeException || _isTlsError(message)) {
      return const ServerError(
        kind: ServerErrorKind.tlsError,
        userMessage:
            'Secure connection failed. '
            'The server may have an invalid certificate or require HTTPS.',
      );
    }

    if (_isServerError(message)) {
      return const ServerError(
        kind: ServerErrorKind.serverError,
        userMessage:
            'The server encountered an internal error. Try again shortly.',
      );
    }

    if (error is FormatException || _isInvalidResponse(message)) {
      return const ServerError(
        kind: ServerErrorKind.invalidResponse,
        userMessage:
            'Server returned an unexpected response. '
            'Verify the URL points to a Re:Link server.',
      );
    }

    return ServerError(
      kind: ServerErrorKind.unknown,
      userMessage: 'Connection failed. Check your network and server address.',
      technicalDetail: message,
    );
  }

  static bool _isBlockedByPolicy(String msg) =>
      msg.contains('Operation not permitted') || msg.contains('errno = 1');

  static bool _isDnsFailure(String msg) =>
      msg.contains('Failed host lookup') ||
      msg.contains('getaddrinfo') ||
      msg.contains('Name or service not known') ||
      msg.contains('nodename nor servname');

  static bool _isConnectionRefused(String msg) =>
      msg.contains('Connection refused') ||
      msg.contains('Connection reset') ||
      msg.contains('No route to host') ||
      msg.contains('Network is unreachable') ||
      msg.contains('ECONNREFUSED') ||
      msg.contains('ECONNRESET') ||
      msg.contains('ENETUNREACH');

  static bool _isTimeout(String msg) =>
      msg.contains('timed out') ||
      msg.contains('TimeoutException') ||
      msg.contains('deadline exceeded');

  static bool _isTlsError(String msg) =>
      msg.contains('HandshakeException') ||
      msg.contains('CERTIFICATE_VERIFY_FAILED') ||
      msg.contains('SSL') ||
      msg.contains('certificate');

  static bool _isServerError(String msg) {
    final statusMatch = RegExp(r'\b5\d{2}\b').firstMatch(msg);
    return statusMatch != null;
  }

  static bool _isInvalidResponse(String msg) =>
      msg.contains('FormatException') ||
      msg.contains('invalid response') ||
      msg.contains('Expected JSON');

  @override
  String toString() => technicalDetail != null
      ? '$userMessage ($technicalDetail)'
      : userMessage;
}
