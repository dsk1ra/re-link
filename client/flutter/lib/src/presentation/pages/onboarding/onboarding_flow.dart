import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:application/src/features/settings/data/local_settings.dart';
import 'package:application/src/presentation/pages/onboarding/onboarding_how_it_works.dart';
import 'package:application/src/presentation/pages/onboarding/onboarding_ice_config.dart';
import 'package:application/src/presentation/pages/onboarding/onboarding_progress_bar.dart';
import 'package:application/src/presentation/pages/onboarding/onboarding_ready.dart';
import 'package:application/src/presentation/pages/onboarding/onboarding_sas.dart';
import 'package:application/src/presentation/pages/onboarding/onboarding_server_config.dart';
import 'package:application/src/presentation/pages/onboarding/onboarding_welcome.dart';
import 'package:application/src/presentation/ui/motion.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/dot_grid_background.dart';

class OnboardingFlow extends StatefulWidget {
  final LocalSettings settings;
  final void Function(String domain) onComplete;

  const OnboardingFlow({
    super.key,
    required this.settings,
    required this.onComplete,
  });

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  static const int _totalPages = 6;

  int _currentPage = 0;
  final Set<int> _completedPages = {};
  bool _isForward = true;

  // Screen 3 — server config
  final TextEditingController _serverAddressController =
      TextEditingController();
  bool? _serverReachable;
  bool _healthCheckLoading = false;

  // Screen 4 — ICE config
  bool _useDefaultIce = true;
  final TextEditingController _stunController = TextEditingController();
  final TextEditingController _turnController = TextEditingController();
  final TextEditingController _turnUsernameController = TextEditingController();
  final TextEditingController _turnCredentialController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    final saved = widget.settings.getDomain();
    if (saved != null) _serverAddressController.text = saved;
  }

  @override
  void dispose() {
    _serverAddressController.dispose();
    _stunController.dispose();
    _turnController.dispose();
    _turnUsernameController.dispose();
    _turnCredentialController.dispose();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────

  void _goToPage(int page) {
    if (page < 0 || page >= _totalPages) return;
    _isForward = page > _currentPage;
    for (int i = 0; i < page; i++) {
      _completedPages.add(i);
    }
    setState(() => _currentPage = page);
    if (page == _totalPages - 1) _recheckHealthIfNeeded();
  }

  void _nextPage() {
    _completedPages.add(_currentPage);
    _isForward = true;
    final next = _currentPage + 1;
    setState(() => _currentPage = next);
    if (next == _totalPages - 1) _recheckHealthIfNeeded();
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _isForward = false;
      setState(() => _currentPage--);
    }
  }

  // ── Health check ────────────────────────────────────────────────────

  Future<void> _checkHealth() async {
    final raw = _serverAddressController.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _healthCheckLoading = true;
      _serverReachable = null;
    });

    try {
      var url = raw;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      if (url.endsWith('/')) url = url.substring(0, url.length - 1);

      final response = await http
          .get(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;
      setState(() {
        _serverReachable = response.statusCode == 200;
        _healthCheckLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _serverReachable = false;
        _healthCheckLoading = false;
      });
    }
  }

  void _recheckHealthIfNeeded() {
    if (_serverAddressController.text.trim().isNotEmpty) {
      _checkHealth();
    }
  }

  // ── Completion ──────────────────────────────────────────────────────

  Future<void> _completeOnboarding() async {
    final domain = _serverAddressController.text.trim();
    await widget.settings.setDomain(domain);

    if (_useDefaultIce) {
      await widget.settings.setIceServersJson('');
      await widget.settings.setIceHost('');
    } else {
      final servers = <Map<String, dynamic>>[];

      final stun = _stunController.text.trim();
      if (stun.isNotEmpty) {
        servers.add({'urls': stun});
      }

      final turn = _turnController.text.trim();
      if (turn.isNotEmpty) {
        final turnEntry = <String, dynamic>{'urls': turn};
        final username = _turnUsernameController.text.trim();
        final credential = _turnCredentialController.text.trim();
        if (username.isNotEmpty) turnEntry['username'] = username;
        if (credential.isNotEmpty) turnEntry['credential'] = credential;
        servers.add(turnEntry);
      }

      if (servers.isNotEmpty) {
        await widget.settings.setIceServersJson(jsonEncode(servers));
      }
    }

    await widget.settings.markWelcomeSeen();

    if (mounted) {
      widget.onComplete(widget.settings.getDomain() ?? domain);
    }
  }

  // ── Screen builders ─────────────────────────────────────────────────

  Widget _buildCurrentScreen() {
    switch (_currentPage) {
      case 0:
        return OnboardingWelcome(
          key: const ValueKey(0),
          onGetStarted: _nextPage,
          onSkipToSetup: () => _goToPage(2),
        );
      case 1:
        return OnboardingHowItWorks(key: const ValueKey(1), onNext: _nextPage);
      case 2:
        return OnboardingServerConfig(
          key: const ValueKey(2),
          serverAddressController: _serverAddressController,
          serverReachable: _serverReachable,
          healthCheckLoading: _healthCheckLoading,
          onCheckHealth: _checkHealth,
          onNext: _nextPage,
        );
      case 3:
        return OnboardingIceConfig(
          key: const ValueKey(3),
          useDefaultIce: _useDefaultIce,
          onToggleDefaultIce: (value) {
            setState(() => _useDefaultIce = value);
          },
          stunController: _stunController,
          turnController: _turnController,
          turnUsernameController: _turnUsernameController,
          turnCredentialController: _turnCredentialController,
          onNext: _nextPage,
        );
      case 4:
        return OnboardingSas(key: const ValueKey(4), onUnderstood: _nextPage);
      case 5:
        return OnboardingReady(
          key: const ValueKey(5),
          serverAddress: _serverAddressController.text.trim(),
          serverReachable: _serverReachable,
          healthCheckLoading: _healthCheckLoading,
          useDefaultIce: _useDefaultIce,
          onOpenReLink: _completeOnboarding,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DotGridBackground(
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): _previousPage,
          },
          child: Focus(
            autofocus: true,
            child: SafeArea(
              child: Column(
                children: [
                  OnboardingProgressBar(
                    currentPage: _currentPage,
                    completedPages: _completedPages,
                    totalPages: _totalPages,
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: AppMotion.standard,
                      switchInCurve: AppMotion.easing,
                      switchOutCurve: AppMotion.easing,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: Offset(_isForward ? 0.04 : -0.04, 0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: AppMotion.easing,
                                  ),
                                ),
                            child: child,
                          ),
                        );
                      },
                      child: _buildCurrentScreen(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
