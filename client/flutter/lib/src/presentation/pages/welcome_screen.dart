import 'package:flutter/material.dart';
import 'package:application/src/features/settings/data/local_settings.dart';

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

  @override
  void initState() {
    super.initState();
    final currentDomain = widget.settings.getDomain();
    _domainController = TextEditingController(text: currentDomain);
  }

  @override
  void dispose() {
    _domainController.dispose();
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
      await widget.settings.markWelcomeSeen();
      if (mounted) {
        widget.onDomainConfigured(widget.settings.getDomain());
      }
    } catch (e) {
      _showError('Error saving domain: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFd8cbc7),
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
                    'Welcome to Rust Remote Desktop',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF1C0F13),
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A privacy-first P2P remote access application',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF1C0F13).withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Setup instructions
                  Card(
                    color: const Color(0xFF1C0F13).withValues(alpha: 0.7),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Server Configuration',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1C0F13),
                                ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Specify the server address you want to connect to.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),

                          // Quick options
                          _buildQuickOption(
                            'Local Development',
                            'localhost:8080',
                            onTap: _setToLocalhost,
                          ),
                          const SizedBox(height: 8),
                          _buildQuickOption(
                            'Custom Domain',
                            'example.com or example.com:8080',
                            onTap: () => _domainController.clear(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Domain input
                  Card(
                    color: Colors.white.withValues(alpha: 0.9),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Server Address',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1C0F13),
                                ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _domainController,
                            decoration: InputDecoration(
                              hintText: 'localhost:8080 or your-domain.com',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
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
                            'Examples: localhost:8080, example.com, relay.example.com:8443',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Colors.grey[600]),
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
                        backgroundColor: const Color(0xFFcc3f0c),
                        foregroundColor: Colors.white,
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

  Widget _buildQuickOption(
    String title,
    String subtitle, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  void _setToLocalhost() {
    _domainController.text = 'localhost:8080';
    setState(() {});
  }
}
