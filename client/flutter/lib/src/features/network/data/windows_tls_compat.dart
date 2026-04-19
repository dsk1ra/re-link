import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

bool _isTryCloudflareHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'trycloudflare.com' ||
      normalized.endsWith('.trycloudflare.com');
}

bool _shouldUseWindowsTlsCompatibility(Uri uri) {
  if (!Platform.isWindows) return false;
  if ((uri.scheme != 'https' && uri.scheme != 'wss') || uri.host.isEmpty) {
    return false;
  }
  // Cloudflare-managed cert chains are trusted on Windows; keep strict TLS.
  if (_isTryCloudflareHost(uri.host)) {
    return false;
  }
  return !_isLoopbackHost(uri.host);
}

HttpClient _createWindowsTlsCompatibilityHttpClient(String expectedHost) {
  final client = HttpClient();
  final normalizedExpectedHost = expectedHost.toLowerCase();
  // Windows compatibility fallback for production servers with broken chains.
  client.badCertificateCallback =
      (X509Certificate cert, String host, int port) {
        return host.toLowerCase() == normalizedExpectedHost;
      };
  return client;
}

http.Client createPlatformHttpClientForBaseUrl(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || !_shouldUseWindowsTlsCompatibility(uri)) {
    return http.Client();
  }
  return IOClient(_createWindowsTlsCompatibilityHttpClient(uri.host));
}

IOWebSocketChannel connectPlatformWebSocket(String wsUrl) {
  final uri = Uri.parse(wsUrl);
  if (!_shouldUseWindowsTlsCompatibility(uri)) {
    return IOWebSocketChannel.connect(uri);
  }
  return IOWebSocketChannel.connect(
    uri,
    customClient: _createWindowsTlsCompatibilityHttpClient(uri.host),
  );
}
