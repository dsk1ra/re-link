import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local settings storage for domain and onboarding state
class LocalSettings {
  static const String _keyDomain = 'signaling_domain';
  static const String _keyIceHost = 'webrtc_ice_host';
  static const String _keyIceServersJson = 'webrtc_ice_servers_json';
  static const String _keyWelcomeShown = 'welcome_shown';
  static const int _defaultStunPort = 3478;
  static const String _defaultPublicStunUrl = 'stun:stun.l.google.com:19302';

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

  /// Returns an optional host or host:port dedicated to ICE/STUN.
  ///
  /// This lets the app use a different public endpoint for ICE than for
  /// signaling, which is required when signaling is exposed through an
  /// HTTPS-only proxy such as Cloudflare Tunnel.
  String? getIceHost() {
    return _prefs.getString(_keyIceHost);
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

  /// Build a STUN URL from an explicit ICE host or endpoint.
  String defaultStunUrlForIceHost(String iceHost) {
    final endpoint = _endpointWithDefaultPort(iceHost);
    return 'stun:$endpoint';
  }

  /// Build a fallback STUN URL from the signaling domain.
  ///
  /// This is only used when no dedicated ICE host is configured.
  String defaultStunUrlForSignalingDomain(String signalingDomain) {
    final normalized = _normalizeIceHost(signalingDomain);
    if (normalized == null) {
      return _defaultPublicStunUrl;
    }

    if (_isTunnelLikeHost(normalized)) {
      return _defaultPublicStunUrl;
    }

    return defaultStunUrlForIceHost(normalized);
  }

  /// Build default ICE JSON from signaling domain.
  ///
  /// A saved or explicitly provided ICE host takes precedence over the
  /// signaling host so the app can keep signaling and ICE on separate
  /// endpoints.
  String defaultIceServersJsonForSignalingDomain(
    String signalingDomain, {
    String? iceHost,
  }) {
    final explicitIceHost = _normalizeIceHost(iceHost ?? getIceHost());
    final stunUrl = explicitIceHost != null
        ? defaultStunUrlForIceHost(explicitIceHost)
        : defaultStunUrlForSignalingDomain(signalingDomain);
    return jsonEncode([
      {
        'urls': stunUrl,
      },
    ]);
  }

  /// Explain the assumption behind the same-host default ICE configuration.
  String defaultIceDescriptionForSignalingDomain(
    String signalingDomain, {
    String? iceHost,
  }) {
    final normalizedIceHost = _normalizeIceHost(iceHost ?? getIceHost());
    final defaultStunUrl = normalizedIceHost != null
        ? defaultStunUrlForIceHost(normalizedIceHost)
        : defaultStunUrlForSignalingDomain(signalingDomain);
    final normalized = signalingDomain.trim();
    final explicitIceHost = (iceHost ?? getIceHost())?.trim();

    if (normalized.isEmpty &&
        (explicitIceHost == null || explicitIceHost.isEmpty)) {
      return 'Generated ICE uses STUN at $defaultStunUrl. '
          'Enter a signaling server and, when needed, a separate public ICE host.';
    }

    if (explicitIceHost != null && explicitIceHost.isNotEmpty) {
      return 'Generated ICE uses the dedicated public ICE host at $defaultStunUrl. '
          'Use this when signaling and STUN/TURN are exposed on different endpoints.';
    }

    return 'Generated ICE falls back to $defaultStunUrl. If signaling is behind '
        'Cloudflare Tunnel or another HTTPS-only proxy, set a separate public '
        'ICE host or TURN server for better reachability.';
  }

  /// Return user-custom ICE config when present; otherwise return domain default.
  List<Map<String, dynamic>> resolveIceServersForSignalingDomain(
    String signalingDomain,
  ) {
    final custom = getIceServers();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }

    final explicitIceHost = _normalizeIceHost(getIceHost());
    final stunUrl = explicitIceHost != null
        ? defaultStunUrlForIceHost(explicitIceHost)
        : defaultStunUrlForSignalingDomain(signalingDomain);

    return [
      {'urls': stunUrl},
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

  /// Save a dedicated ICE host or endpoint. Pass empty text to clear it.
  Future<void> setIceHost(String iceHost) async {
    final normalized = _normalizeIceHost(iceHost);
    if (normalized == null) {
      await _prefs.remove(_keyIceHost);
      return;
    }

    await _prefs.setString(_keyIceHost, normalized);
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

  String _endpointWithDefaultPort(String rawHost) {
    final normalized = _normalizeIceHost(rawHost);
    if (normalized == null) {
      return 'localhost:$_defaultStunPort';
    }

    if (_hasExplicitPort(normalized)) {
      return normalized;
    }

    if (_looksLikeBareIpv6(normalized)) {
      return '[$normalized]:$_defaultStunPort';
    }

    return '$normalized:$_defaultStunPort';
  }

  String? _normalizeIceHost(String? rawHost) {
    if (rawHost == null) {
      return null;
    }

    var normalized = rawHost.trim();
    if (normalized.isEmpty) {
      return null;
    }

    normalized = normalized.replaceFirst(RegExp(r'^(stun|turn|turns):'), '');
    if (normalized.startsWith('//')) {
      normalized = normalized.substring(2);
    }

    final withScheme =
        normalized.startsWith('http://') || normalized.startsWith('https://')
        ? normalized
        : 'https://$normalized';

    final uri = Uri.tryParse(withScheme);
    if (uri != null && uri.host.isNotEmpty) {
      final host = _looksLikeBareIpv6(uri.host) ? '[${uri.host}]' : uri.host;
      return uri.hasPort ? '$host:${uri.port}' : host;
    }

    normalized = normalized.split('/').first.split('?').first.split('#').first;
    return normalized.isEmpty ? null : normalized;
  }

  bool _hasExplicitPort(String hostOrEndpoint) {
    if (hostOrEndpoint.startsWith('[')) {
      return hostOrEndpoint.contains(']:');
    }

    return ':'.allMatches(hostOrEndpoint).length == 1;
  }

  bool _looksLikeBareIpv6(String hostOrEndpoint) {
    return hostOrEndpoint.contains(':') &&
        !hostOrEndpoint.startsWith('[') &&
        ':'.allMatches(hostOrEndpoint).length > 1;
  }

  bool _isTunnelLikeHost(String hostOrEndpoint) {
    final normalized = hostOrEndpoint.toLowerCase();
    return normalized == 'trycloudflare.com' ||
        normalized.endsWith('.trycloudflare.com');
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
    await _prefs.remove(_keyIceHost);
    await _prefs.remove(_keyIceServersJson);
    await _prefs.remove(_keyWelcomeShown);
  }
}
