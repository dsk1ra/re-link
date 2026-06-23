import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:application/src/presentation/pages/onboarding/onboarding_flow.dart';
import 'package:application/src/presentation/pages/connection_pairing_page.dart';
import 'package:application/src/presentation/ui/theme.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/features/pairing/data/http/http_signaling_backend.dart';
import 'package:application/src/features/settings/data/local_settings.dart';
import 'package:application/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final settings = LocalSettings(prefs);
  if (_shouldResetAppPrefs()) {
    await settings.reset();
  }

  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen((record) {
    final loggerName = record.loggerName;
    final prefix = loggerName.isEmpty
        ? record.level.name
        : '${record.level.name}: $loggerName';
    debugPrint('$prefix: ${record.message}');
  });
  await RustLib.init();
  runApp(const MyApp());
}

bool _shouldResetAppPrefs() {
  const resetFromDefine = bool.fromEnvironment('RESET_APP_PREFS');
  final resetFromEnv = Platform.environment['RESET_APP_PREFS'];
  return resetFromDefine ||
      (resetFromEnv != null &&
          resetFromEnv.isNotEmpty &&
          resetFromEnv != '0' &&
          resetFromEnv.toLowerCase() != 'false');
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
      title: 'Re:Link',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
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

          if (!settings.hasSeenWelcome() || !settings.hasDomain()) {
            return OnboardingFlow(
              settings: settings,
              onComplete: (domain) {
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
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.action),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'INITIALIZING',
              style: AppTypography.eyebrow.copyWith(
                color: AppColors.textMuted,
              ),
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
            Text(
              'INITIALIZATION FAILED',
              style: AppTypography.eyebrow.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 16),
            Text('Initialization Error', style: AppTypography.h1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                error,
                style: AppTypography.data.copyWith(
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
