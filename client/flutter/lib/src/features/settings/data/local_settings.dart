import 'package:shared_preferences/shared_preferences.dart';

/// Local settings storage for domain and onboarding state
class LocalSettings {
  static const String _keyDomain = 'signaling_domain';
  static const String _keyWelcomeShown = 'welcome_shown';

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
    await _prefs.remove(_keyWelcomeShown);
  }
}
