import 'package:flutter/material.dart';
import 'package:application/src/features/settings/data/local_settings.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

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
  late TextEditingController _iceServersController;

  @override
  void initState() {
    super.initState();
    _domainController = TextEditingController();
    _iceServersController = TextEditingController(
      text: widget.settings.getIceServersJson() ?? '',
    );
  }

  @override
  void dispose() {
    _domainController.dispose();
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
      await widget.settings.setIceServersJson(_iceServersController.text);
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
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 16 : 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Welcome header
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to ReLink',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A privacy-first P2P remote access application',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Domain input
                  Card(
                    color: AppColors.surfaceVariant,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Server Address',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _domainController,
                            cursorColor: AppColors.primary,
                            style: const TextStyle(color: AppColors.textMuted),
                            decoration: InputDecoration(
                              hintText:
                                  'https://your-domain.com or localhost:8080',
                              hintStyle: const TextStyle(
                                color: AppColors.textMuted,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.outline,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Examples: localhost:8080, https://example.com, relay.example.com:8443',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Optional ICE Servers (JSON)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _iceServersController,
                            maxLines: 4,
                            cursorColor: AppColors.primary,
                            style: const TextStyle(color: AppColors.textMuted),
                            decoration: InputDecoration(
                              hintText:
                                  '[{"urls":"stun:stun.l.google.com:19302"},{"urls":["turn:turn.example.com:3478?transport=udp"],"username":"user","credential":"pass"}]',
                              hintStyle: const TextStyle(
                                color: AppColors.textMuted,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.outline,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.outline,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Action buttons
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveDomain,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
