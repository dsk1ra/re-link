import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:application/src/presentation/pages/welcome_screen.dart';
import 'package:application/src/presentation/pages/connection_pairing_page.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/features/pairing/data/http/http_signaling_backend.dart';
import 'package:application/src/features/settings/data/local_settings.dart';
import 'package:application/src/rust/frb_generated.dart';

Future<void> main() async {
  // Reset preferences if RESET_APP_PREFS environment variable is set
  final shouldResetPrefs = Platform.environment.containsKey('RESET_APP_PREFS');
  if (shouldResetPrefs) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    debugPrint('Preferences cleared. Welcome screen will show on next launch.');
  }
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    debugPrint(
      '${record.level.name}: ${record.time.toIso8601String()} '
      '${record.loggerName}: ${record.message}',
    );
    if (record.error != null) {
      debugPrint('Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      debugPrint(record.stackTrace.toString());
    }
  });
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<LocalSettings> _settingsFuture;

  @override
  void initState() {
    super.initState();
    _settingsFuture = _initializeSettings();
  }

  Future<LocalSettings> _initializeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalSettings(prefs);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReLink',
      debugShowCheckedModeBanner: false,
      home: FutureBuilder<LocalSettings>(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingScreen();
          }

          if (snapshot.hasError) {
            return _ErrorScreen(error: snapshot.error.toString());
          }

          final settings = snapshot.data!;
          final configuredDomain = settings.getDomain();

          // Show welcome until the user has both seen onboarding and set a domain.
          if (!settings.hasSeenWelcome() || !settings.hasDomain()) {
            return WelcomeScreen(
              settings: settings,
              onDomainConfigured: (domain) {
                // After welcome, navigate to main pairing page
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => _PairingPageWrapper(
                      settings: settings,
                      initialDomain: domain,
                    ),
                  ),
                );
              },
            );
          }

          // Otherwise, go straight to pairing page
          return _PairingPageWrapper(
            settings: settings,
            initialDomain: configuredDomain!,
          );
        },
      ),
    );
  }
}

/// Wrapper that creates the pairing page with proper backend initialization
class _PairingPageWrapper extends StatefulWidget {
  final LocalSettings settings;
  final String initialDomain;

  const _PairingPageWrapper({
    required this.settings,
    required this.initialDomain,
  });

  @override
  State<_PairingPageWrapper> createState() => _PairingPageWrapperState();
}

class _PairingPageWrapperState extends State<_PairingPageWrapper> {
  late String _currentDomain;
  late HttpSignalingBackend _backend;

  @override
  void initState() {
    super.initState();
    _currentDomain = widget.initialDomain;
    _backend = HttpSignalingBackend(_currentDomain);
  }

  @override
  void dispose() {
    _backend.dispose();
    super.dispose();
  }

  Future<void> _handleDomainChange(String newDomain) async {
    if (newDomain != _currentDomain) {
      final oldBackend = _backend;
      setState(() {
        _currentDomain = newDomain;
        _backend = HttpSignalingBackend(_currentDomain);
      });
      oldBackend.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConnectionPairingPage(
      key: ValueKey(_currentDomain),
      signalingBaseUrl: _currentDomain,
      backend: _backend,
      settings: widget.settings,
      onDomainChanged: _handleDomainChange,
    );
  }
}

/// Loading screen shown while initializing settings
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'Loading...',
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error screen shown if initialization fails
class _ErrorScreen extends StatelessWidget {
  final String error;

  const _ErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Initialization Error',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                error,
                style: const TextStyle(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
