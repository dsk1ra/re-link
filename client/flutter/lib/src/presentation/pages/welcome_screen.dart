import 'package:flutter/material.dart';
import 'package:application/src/features/settings/data/local_settings.dart';
import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';
import 'package:application/src/presentation/widgets/app_card.dart';

/// Welcome and domain setup screen shown on first launch
class WelcomeScreen extends StatefulWidget {
  final LocalSettings settings;
  final Function(String domain) onDomainConfigured;

  const WelcomeScreen({
    super.key,
    required this.settings,
    required this.onDomainConfigured,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late TextEditingController _domainController;
  late TextEditingController _iceHostController;
  late TextEditingController _iceServersController;
  late bool _useDefaultIceForDomain;

  @override
  void initState() {
    super.initState();
    final savedDomain = widget.settings.getDomain() ?? '';
    final savedIceHost = widget.settings.getIceHost() ?? '';
    final savedIceServersJson = widget.settings.getIceServersJson();

    _useDefaultIceForDomain =
        savedIceServersJson == null || savedIceServersJson.trim().isEmpty;

    _domainController = TextEditingController(text: savedDomain);
    _iceHostController = TextEditingController(text: savedIceHost);
    _iceServersController = TextEditingController(
      text: _useDefaultIceForDomain
          ? widget.settings.defaultIceServersJsonForSignalingDomain(
              savedDomain,
              iceHost: savedIceHost,
            )
          : (savedIceServersJson ?? ''),
    );
  }

  @override
  void dispose() {
    _domainController.dispose();
    _iceHostController.dispose();
    _iceServersController.dispose();
    super.dispose();
  }

  Future<void> _saveDomain() async {
    final domain = _domainController.text.trim();
    if (domain.isEmpty) {
      _showError('Please enter a domain or server address');
      return;
    }

    try {
      await widget.settings.setDomain(domain);
      await widget.settings.setIceHost(_iceHostController.text);
      if (_useDefaultIceForDomain) {
        await widget.settings.setIceServersJson('');
      } else {
        await widget.settings.setIceServersJson(_iceServersController.text);
      }
      await widget.settings.markWelcomeSeen();
      if (mounted) {
        widget.onDomainConfigured(widget.settings.getDomain() ?? domain);
      }
    } catch (e) {
      _showError('Error saving domain: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.label.copyWith(color: AppColors.error),
        ),
      ),
    );
  }

  String _defaultIceServersJsonForCurrentDomain() {
    return widget.settings.defaultIceServersJsonForSignalingDomain(
      _domainController.text.trim(),
      iceHost: _iceHostController.text.trim(),
    );
  }

  String _defaultIceDescriptionForCurrentDomain() {
    return widget.settings.defaultIceDescriptionForSignalingDomain(
      _domainController.text,
      iceHost: _iceHostController.text,
    );
  }

  void _syncDefaultIceServersFromDomain() {
    if (!_useDefaultIceForDomain) {
      return;
    }

    final nextValue = _defaultIceServersJsonForCurrentDomain();
    _iceServersController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text.toUpperCase(), style: AppTypography.eyebrow),
    );
  }

  Widget _helperText(String text) {
    return Text(
      text,
      style: AppTypography.caption.copyWith(color: AppColors.textFaint),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final defaultIceJson = _defaultIceServersJsonForCurrentDomain();
    final defaultIceDescription = _defaultIceDescriptionForCurrentDomain();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppUiMetrics.formWidth,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'RE:LINK',
                    style: AppTypography.eyebrow.copyWith(
                      color: AppColors.action,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Welcome', style: AppTypography.h1),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Server-blind, ephemeral peer-to-peer remote access. '
                    'Point the client at your Re:Link server to begin — '
                    'the server brokers the rendezvous and sees nothing else.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppCard(
                    eyebrow: 'Server configuration',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('Server address'),
                        TextField(
                          controller: _domainController,
                          style: AppTypography.data,
                          decoration: const InputDecoration(
                            hintText:
                                'https://your-domain.com or localhost:8080',
                          ),
                          onChanged: (_) {
                            setState(_syncDefaultIceServersFromDomain);
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _helperText(
                          'localhost:8080 · https://example.com · '
                          'relay.example.com:8443',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _sectionLabel('Public ICE host (optional)'),
                        TextField(
                          controller: _iceHostController,
                          style: AppTypography.data,
                          decoration: const InputDecoration(
                            hintText:
                                '203.0.113.10, stun.example.com, or host:3478',
                          ),
                          onChanged: (_) {
                            setState(_syncDefaultIceServersFromDomain);
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _helperText(
                          'Set this when signaling and STUN/TURN are exposed '
                          'on different public endpoints.',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _sectionLabel('ICE servers (STUN/TURN JSON)'),
                        SwitchListTile.adaptive(
                          value: _useDefaultIceForDomain,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Use generated STUN config',
                            style: AppTypography.label,
                          ),
                          subtitle: Text(
                            defaultIceJson.isEmpty
                                ? 'Enter server address to preview default STUN JSON'
                                : defaultIceJson,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textFaint,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _useDefaultIceForDomain = value;
                              if (_useDefaultIceForDomain) {
                                _syncDefaultIceServersFromDomain();
                              }
                            });
                          },
                        ),
                        Text(
                          defaultIceDescription,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _iceServersController,
                          maxLines: 4,
                          enabled: !_useDefaultIceForDomain,
                          style: AppTypography.data,
                          decoration: const InputDecoration(
                            hintText:
                                '[{"urls":"stun:your-domain-or-ip:3478"},{"urls":["turn:turn.example.com:3478?transport=udp"],"username":"user","credential":"pass"}]',
                          ),
                          onChanged: (_) => setState(() {
                            _useDefaultIceForDomain = false;
                          }),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _helperText(
                          'If you expose signaling through Cloudflare Tunnel, '
                          'keep the server address as the tunnel URL and '
                          'enter a separate public STUN/TURN host or IP here.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(onPressed: _saveDomain, label: 'Continue'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
