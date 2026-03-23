import 'dart:async';

import 'package:flutter/material.dart';
import 'package:application/src/features/pairing/domain/signaling_backend.dart';
import 'package:application/src/features/settings/data/local_settings.dart';
import 'package:application/src/presentation/pages/initiator_page.dart';
import 'package:application/src/presentation/pages/responder_page.dart';
import 'package:application/src/presentation/ui/metrics.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_card.dart';
import 'package:application/src/presentation/widgets/domain_config_dialog.dart';
import 'package:application/src/presentation/widgets/server_status_banner.dart';

/// Main launcher page for P2P connection
class ConnectionPairingPage extends StatefulWidget {
  final String signalingBaseUrl;
  final SignalingBackend backend;
  final LocalSettings? settings;
  final Function(String)? onDomainChanged;

  const ConnectionPairingPage({
    super.key,
    this.signalingBaseUrl = 'http://127.0.0.1:8080',
    required this.backend,
    this.settings,
    this.onDomainChanged,
  });

  @override
  State<ConnectionPairingPage> createState() => _ConnectionPairingPageState();
}

class _ConnectionPairingPageState extends State<ConnectionPairingPage> {
  static const double _horizontalLayoutBreakpoint = 720;
  static const double _maxContentWidth = 900;
  static const double _cardBorderRadius = 16;
  static const double _titleFontSize = 28;
  static const double _cardTitleFontSize = 18;
  static const double _cardSubtitleFontSize = 12;

  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() => _connectToServer());
  }

  Future<void> _connectToServer() async {
    setState(() {
      _connecting = true;
    });

    try {
      await widget.backend.register(deviceLabel: 'Flutter P2P Client');
      setState(() => _connecting = false);
    } catch (e) {
      setState(() {
        _connecting = false;
      });
      _showSnackBar('Connection failed: $e');
    }
  }

  void _navigateToInitiator() {
    if (!widget.backend.isRegistered) {
      _showSnackBar('Not connected to server');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InitiatorPage(
          signalingBaseUrl: widget.signalingBaseUrl,
          backend: widget.backend,
        ),
      ),
    );
  }

  void _navigateToResponder() {
    if (!widget.backend.isRegistered) {
      _showSnackBar('Not connected to server');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResponderPage(
          signalingBaseUrl: widget.signalingBaseUrl,
          backend: widget.backend,
        ),
      ),
    );
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
    final connected = widget.backend.isRegistered;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'P2P Connect',
          style: AppTypography.title(size: AppUiMetrics.appBarTitleFontSize),
        ),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          if (widget.settings != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Change server address',
                onPressed: _showDomainConfigDialog,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          ServerStatusBanner(
            connecting: _connecting,
            connected: connected,
            connectedText: widget.backend.displayName ?? 'Connected to server',
            onRetry: _connectToServer,
          ),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useHorizontalActions =
                    constraints.maxWidth >= _horizontalLayoutBreakpoint;

                Widget buildActionCard({
                  required String title,
                  required String subtitle,
                  required VoidCallback onTap,
                }) {
                  return AppCard(
                    variant: connected
                        ? AppCardVariant.normal
                        : AppCardVariant.warning,
                    child: InkWell(
                      onTap: connected ? onTap : null,
                      borderRadius: BorderRadius.circular(_cardBorderRadius),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppTypography.title(
                                size: _cardTitleFontSize,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              subtitle,
                              style: AppTypography.body(
                                size: _cardSubtitleFontSize,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final actions = useHorizontalActions
                    ? Row(
                        children: [
                          Expanded(
                            child: buildActionCard(
                              title: 'Create Connection',
                              subtitle: 'Generate a link to share',
                              onTap: _navigateToInitiator,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.base),
                          Expanded(
                            child: buildActionCard(
                              title: 'Join Connection',
                              subtitle: 'Use a shared link',
                              onTap: _navigateToResponder,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          buildActionCard(
                            title: 'Create Connection',
                            subtitle: 'Generate a link to share',
                            onTap: _navigateToInitiator,
                          ),
                          const SizedBox(height: AppSpacing.base),
                          buildActionCard(
                            title: 'Join Connection',
                            subtitle: 'Use a shared link',
                            onTap: _navigateToResponder,
                          ),
                        ],
                      );

                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _maxContentWidth,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Peer-to-Peer Connection',
                            style: AppTypography.title(size: _titleFontSize),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.base),
                          Text(
                            'Secure, direct connection with minimal server involvement',
                            style: AppTypography.body(
                              color: AppColors.textMuted,
                            ),
                            textAlign: TextAlign.center,
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
    );
  }
}
