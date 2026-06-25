import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:application/src/features/network/data/server_error.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/features/network/data/windows_tls_compat.dart';
import 'package:application/src/features/settings/data/local_settings.dart';
import 'package:application/src/presentation/pages/initiator_page.dart';
import 'package:application/src/presentation/pages/responder_page.dart';
import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_card.dart';
import 'package:application/src/presentation/widgets/domain_config_dialog.dart';
import 'package:application/src/presentation/widgets/dot_grid_background.dart';
import 'package:application/src/presentation/widgets/server_status_banner.dart';

/// Main launcher page for P2P connection
class ConnectionPairingPage extends StatefulWidget {
  final String signalingBaseUrl;
  final SignalingBackend backend;
  final LocalSettings? settings;
  final Function(String)? onDomainChanged;

  const ConnectionPairingPage({
    super.key,
    required this.signalingBaseUrl,
    required this.backend,
    this.settings,
    this.onDomainChanged,
  });

  @override
  State<ConnectionPairingPage> createState() => _ConnectionPairingPageState();
}

class _ConnectionPairingPageState extends State<ConnectionPairingPage> {
  static const double _horizontalLayoutBreakpoint = 720;
  static const Duration _healthCheckTimeout = Duration(seconds: 8);

  bool _connecting = false;
  bool _serverReachable = false;
  String? _serverErrorMessage;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() => _connectToServer());
  }

  Future<void> _connectToServer() async {
    setState(() {
      _connecting = true;
      _serverErrorMessage = null;
    });

    final client = createPlatformHttpClientForBaseUrl(widget.signalingBaseUrl);
    try {
      final response = await client.get(
        Uri.parse('${widget.signalingBaseUrl}/health'),
      ).timeout(_healthCheckTimeout);
      final reachable = response.statusCode == 200;
      setState(() {
        _serverReachable = reachable;
        _connecting = false;
        if (!reachable) {
          _serverErrorMessage =
              'Server returned status ${response.statusCode}. '
              'Verify the URL points to a Re:Link server.';
        }
      });
    } catch (e) {
      final classified = ServerError.classify(e);
      setState(() {
        _serverReachable = false;
        _connecting = false;
        _serverErrorMessage = classified.userMessage;
      });
    } finally {
      client.close();
    }
  }

  void _navigateToInitiator() {
    if (!_serverReachable) {
      _showSnackBar('Not connected to server');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InitiatorPage(
          signalingBaseUrl: widget.signalingBaseUrl,
          backend: widget.backend,
          iceServers: _configuredIceServers(),
        ),
      ),
    );
  }

  void _navigateToResponder() {
    if (!_serverReachable) {
      _showSnackBar(
        'Configured server is unreachable. Paste a full invite link to use its server URL.',
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResponderPage(
          signalingBaseUrl: widget.signalingBaseUrl,
          backend: widget.backend,
          iceServers: _configuredIceServers(),
        ),
      ),
    );
  }

  List<Map<String, dynamic>>? _configuredIceServers() {
    final settings = widget.settings;
    if (settings == null) {
      return null;
    }

    final parsed = settings.resolveIceServersForSignalingDomain(
      widget.signalingBaseUrl,
    );

    // Deep copy to avoid accidental mutation across pages.
    return parsed
        .map(
          (server) =>
              Map<String, dynamic>.from(jsonDecode(jsonEncode(server)) as Map),
        )
        .toList();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDomainConfigDialog() async {
    if (widget.settings == null) return;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => DomainConfigDialog(
        settings: widget.settings!,
        onDomainChanged: (domain) {
          widget.onDomainChanged?.call(domain);
        },
      ),
    );

    if (result != null) {
      _showSnackBar('Server address updated to: $result');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _serverReachable;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('RE:LINK'),
        actions: [
          if (widget.settings != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: IconButton(
                icon: const Icon(LucideIcons.settings2),
                tooltip: 'Change server address',
                onPressed: _showDomainConfigDialog,
              ),
            ),
        ],
      ),
      body: DotGridBackground(
        child: Column(
          children: [
            ServerStatusBanner(
              connecting: _connecting,
              connected: connected,
              connectedText: 'Connected to server',
              errorDetail: _serverErrorMessage,
              onRetry: _connectToServer,
            ),

            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useHorizontalActions =
                      constraints.maxWidth >= _horizontalLayoutBreakpoint;

                  Widget buildActionCard({
                    required String eyebrow,
                    required String title,
                    required String subtitle,
                    required VoidCallback onTap,
                    required bool enabled,
                  }) {
                    final titleColor = enabled
                        ? AppColors.textPrimary
                        : AppColors.textFaint;
                    final subtitleColor = enabled
                        ? AppColors.textMuted
                        : AppColors.textFaint;
                    return AppCard(
                      padding: EdgeInsets.zero,
                      emphasized: enabled,
                      child: InkWell(
                        onTap: enabled ? onTap : null,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                eyebrow.toUpperCase(),
                                style: AppTypography.eyebrow.copyWith(
                                  color: enabled
                                      ? AppColors.action
                                      : AppColors.textFaint,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                title,
                                style: AppTypography.h2.copyWith(
                                  color: titleColor,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                subtitle,
                                style: AppTypography.body.copyWith(
                                  color: subtitleColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final actions = useHorizontalActions
                      ? IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: buildActionCard(
                                  eyebrow: 'Initiate',
                                  title: 'Create connection',
                                  subtitle: 'Generate a link to share',
                                  onTap: _navigateToInitiator,
                                  enabled: connected,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.lg),
                              Expanded(
                                child: buildActionCard(
                                  eyebrow: 'Respond',
                                  title: 'Join connection',
                                  subtitle: 'Use a shared link',
                                  onTap: _navigateToResponder,
                                  enabled: true,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            buildActionCard(
                              eyebrow: 'Initiate',
                              title: 'Create connection',
                              subtitle: 'Generate a link to share',
                              onTap: _navigateToInitiator,
                              enabled: connected,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            buildActionCard(
                              eyebrow: 'Respond',
                              title: 'Join connection',
                              subtitle: 'Use a shared link',
                              onTap: _navigateToResponder,
                              enabled: true,
                            ),
                          ],
                        );

                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppUiMetrics.maxContentWidth,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SESSION', style: AppTypography.eyebrow),
                            const SizedBox(height: AppSpacing.sm),
                            Text('Start a session', style: AppTypography.h1),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Direct peer-to-peer connection, brokered by a '
                              'rendezvous server that sees nothing else.',
                              style: AppTypography.body.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            actions,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
