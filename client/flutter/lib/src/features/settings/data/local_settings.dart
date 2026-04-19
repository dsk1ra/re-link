import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local settings storage for domain and onboarding state
class LocalSettings {
  static const String _keyDomain = 'signaling_domain';
  static const String _keyIceServersJson = 'webrtc_ice_servers_json';
  static const String _keyWelcomeShown = 'welcome_shown';
  static const int _defaultStunPort = 3478;
  static const String _publicFallbackStunUrl = 'stun:stun.l.google.com:19302';

  final SharedPreferences _prefs;

  LocalSettings(this._prefs);

  /// Get the stored signaling domain, or null if not configured yet
  String? getDomain() {
    return _prefs.getString(_keyDomain);
  }

  /// Check whether a signaling domain is configured
  bool hasDomain() {
    final domain = getDomain();
    return domain != null && domain.trim().isNotEmpty;
  }

  /// Returns raw ICE servers JSON configured by the user (if any).
  String? getIceServersJson() {
    return _prefs.getString(_keyIceServersJson);
  }

  /// Parse and sanitize ICE server configuration for flutter_webrtc.
  ///
  /// Expected format:
  /// [
  ///   {"urls": "stun:your-domain-or-ip:3478"},
  ///   {
  ///     "urls": ["turn:turn.example.com:3478?transport=udp"],
  ///     "username": "user",
  ///     "credential": "pass"
  ///   }
  /// ]
  List<Map<String, dynamic>>? getIceServers() {
    final raw = getIceServersJson();
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      return _sanitizeIceServers(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Build default STUN URL from the configured signaling domain.
  ///
  /// For normal direct hosts we assume a colocated STUN service on port 3478.
  /// For tunnel-only hosts such as `*.trycloudflare.com`, UDP/STUN on 3478
  /// is not available, so we fall back to a public STUN server.
  String defaultStunUrlForSignalingDomain(String signalingDomain) {
    final normalized = signalingDomain.trim();
    if (normalized.isEmpty) {
      return 'stun:localhost:$_defaultStunPort';
    }

    final withScheme =
        normalized.startsWith('http://') || normalized.startsWith('https://')
        ? normalized
        : 'https://$normalized';

    final uri = Uri.tryParse(withScheme);
    final fallbackHost = normalized
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .split(':')
        .first;
    final host = (uri != null && uri.host.isNotEmpty) ? uri.host : fallbackHost;

    if (_shouldUsePublicStunFallback(host)) {
      return _publicFallbackStunUrl;
    }

    return 'stun:$host:$_defaultStunPort';
  }

  bool _shouldUsePublicStunFallback(String host) {
    final normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.isEmpty) {
      return false;
    }

    return normalizedHost == 'trycloudflare.com' ||
        normalizedHost.endsWith('.trycloudflare.com');
  }

  /// Build default ICE JSON from signaling domain.
  String defaultIceServersJsonForSignalingDomain(String signalingDomain) {
    return jsonEncode([
      {'urls': defaultStunUrlForSignalingDomain(signalingDomain)},
    ]);
  }

  /// Return user-custom ICE config when present; otherwise return domain default.
  List<Map<String, dynamic>> resolveIceServersForSignalingDomain(
    String signalingDomain,
  ) {
    final custom = getIceServers();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }

    return [
      {'urls': defaultStunUrlForSignalingDomain(signalingDomain)},
    ];
  }

  /// Save ICE servers as JSON; pass empty text to clear custom config.
  Future<void> setIceServersJson(String iceServersJson) async {
    final trimmed = iceServersJson.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(_keyIceServersJson);
      return;
    }

    final parsed = jsonDecode(trimmed);
    final sanitized = _sanitizeIceServers(parsed);
    if (sanitized == null || sanitized.isEmpty) {
      throw const FormatException(
        'ICE servers JSON must be a non-empty array with valid "urls" entries',
      );
    }

    await _prefs.setString(_keyIceServersJson, jsonEncode(sanitized));
  }

  List<Map<String, dynamic>>? _sanitizeIceServers(dynamic raw) {
    if (raw is! List) {
      return null;
    }

    final sanitized = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(item);
      final urls = map['urls'];
      final normalizedUrls = _normalizeIceUrls(urls);
      if (normalizedUrls == null) {
        continue;
      }

      final server = <String, dynamic>{'urls': normalizedUrls};

      final username = map['username'];
      if (username is String && username.isNotEmpty) {
        server['username'] = username;
      }

      final credential = map['credential'];
      if (credential is String && credential.isNotEmpty) {
        server['credential'] = credential;
      }

      sanitized.add(server);
    }

    return sanitized.isEmpty ? null : sanitized;
  }

  dynamic _normalizeIceUrls(dynamic rawUrls) {
    if (rawUrls is String && rawUrls.isNotEmpty) {
      return rawUrls;
    }
    if (rawUrls is List) {
      final urls = rawUrls
          .whereType<String>()
          .where((u) => u.isNotEmpty)
          .toList();
      if (urls.isEmpty) {
        return null;
      }
      return urls;
    }
    return null;
  }

  /// Save the signaling domain
  Future<void> setDomain(String domain) async {
    // Normalize the domain (default to HTTPS when scheme is omitted)
    String normalizedDomain = domain.trim();
    if (!normalizedDomain.startsWith('http://') &&
        !normalizedDomain.startsWith('https://')) {
      normalizedDomain = 'https://$normalizedDomain';
    }
    // Remove trailing slash if present
    if (normalizedDomain.endsWith('/')) {
      normalizedDomain = normalizedDomain.substring(
        0,
        normalizedDomain.length - 1,
      );
    }
    await _prefs.setString(_keyDomain, normalizedDomain);
  }

  /// Check if welcome screen has been shown before
  bool hasSeenWelcome() {
    return _prefs.getBool(_keyWelcomeShown) ?? false;
  }

  /// Mark welcome screen as seen
  Future<void> markWelcomeSeen() async {
    await _prefs.setBool(_keyWelcomeShown, true);
  }

  /// Reset all settings (for testing or app reset)
  Future<void> reset() async {
    await _prefs.remove(_keyDomain);
    await _prefs.remove(_keyIceServersJson);
    await _prefs.remove(_keyWelcomeShown);
  }
}
