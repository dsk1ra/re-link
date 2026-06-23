import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:application/src/features/settings/data/local_settings.dart';
import 'package:application/src/presentation/ui/radius.dart';
import 'package:application/src/presentation/ui/spacing.dart';
import 'package:application/src/presentation/ui/typography.dart';
import 'package:application/src/presentation/ui/ui_config.dart';
import 'package:application/src/presentation/widgets/app_button.dart';

enum _SettingsSection { server, ice }

class DomainConfigDialog extends StatefulWidget {
  final LocalSettings settings;
  final Function(String domain)? onDomainChanged;

  const DomainConfigDialog({
    super.key,
    required this.settings,
    this.onDomainChanged,
  });

  @override
  State<DomainConfigDialog> createState() => _DomainConfigDialogState();
}

class _DomainConfigDialogState extends State<DomainConfigDialog> {
  static const double _dialogWidthFraction = 0.70;
  static const double _dialogHeightFraction = 0.60;
  static const double _maxDialogWidth = 780;
  static const double _maxDialogHeight = 520;
  static const double _minDialogWidth = 480;
  static const double _minDialogHeight = 340;
  static const double _navWidth = 180;

  _SettingsSection _activeSection = _SettingsSection.server;

  late TextEditingController _controller;
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

    _controller = TextEditingController(text: savedDomain);
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
    _controller.dispose();
    _iceHostController.dispose();
    _iceServersController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final domain = _controller.text.trim();
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
      if (mounted) {
        final updatedDomain = widget.settings.getDomain() ?? domain;
        Navigator.pop(context, updatedDomain);
        widget.onDomainChanged?.call(updatedDomain);
      }
    } catch (e) {
      _showError('Error saving: $e');
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
      _controller.text.trim(),
      iceHost: _iceHostController.text.trim(),
    );
  }

  String _defaultIceDescriptionForCurrentDomain() {
    return widget.settings.defaultIceDescriptionForSignalingDomain(
      _controller.text,
      iceHost: _iceHostController.text,
    );
  }

  void _syncDefaultIceServersFromDomain() {
    if (!_useDefaultIceForDomain) return;

    final nextValue = _defaultIceServersJsonForCurrentDomain();
    _iceServersController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
  }

  // ─── Nav items ──────────────────────────────────────────────────────────

  Widget _buildNav() {
    return Container(
      width: _navWidth,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Text('SETTINGS', style: AppTypography.eyebrow),
          ),
          _navItem(
            section: _SettingsSection.server,
            icon: LucideIcons.server,
            label: 'Server',
          ),
          _navItem(
            section: _SettingsSection.ice,
            icon: LucideIcons.network,
            label: 'ICE / STUN',
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required _SettingsSection section,
    required IconData icon,
    required String label,
  }) {
    final selected = _activeSection == section;
    return InkWell(
      onTap: () => setState(() => _activeSection = section),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? AppColors.action : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.textPrimary : AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label.toUpperCase(),
              style: AppTypography.label.copyWith(
                color: selected ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Section content ────────────────────────────────────────────────────

  Widget _buildContent() {
    return switch (_activeSection) {
      _SettingsSection.server => _buildServerSection(),
      _SettingsSection.ice => _buildIceSection(),
    };
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

  Widget _buildServerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Signaling server', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'The signaling server only brokers the rendezvous. '
          'It never sees session keys or content.',
          style: AppTypography.body.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        _sectionLabel('Server address'),
        TextField(
          controller: _controller,
          style: AppTypography.data,
          decoration: const InputDecoration(
            hintText: 'https://your-domain.com or localhost:8080',
          ),
          onChanged: (_) {
            setState(_syncDefaultIceServersFromDomain);
          },
          autofocus: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        _helperText(
          'localhost:8080 · https://example.com · relay.example.com:8443',
        ),
      ],
    );
  }

  Widget _buildIceSection() {
    final defaultIceJson = _defaultIceServersJsonForCurrentDomain();
    final defaultIceDescription = _defaultIceDescriptionForCurrentDomain();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ICE configuration', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'STUN/TURN servers used for WebRTC peer discovery. '
          'Set a dedicated ICE host when signaling runs behind an '
          'HTTPS-only proxy like Cloudflare Tunnel.',
          style: AppTypography.body.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        _sectionLabel('Public ICE host (optional)'),
        TextField(
          controller: _iceHostController,
          style: AppTypography.data,
          decoration: const InputDecoration(
            hintText: '203.0.113.10, stun.example.com, or host:3478',
          ),
          onChanged: (_) {
            setState(_syncDefaultIceServersFromDomain);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _helperText(
          'Set this when signaling and STUN/TURN are exposed on '
          'different public endpoints.',
        ),
        const SizedBox(height: AppSpacing.lg),
        _sectionLabel('ICE servers (STUN/TURN JSON)'),
        SwitchListTile.adaptive(
          value: _useDefaultIceForDomain,
          contentPadding: EdgeInsets.zero,
          title: Text('Use generated STUN config', style: AppTypography.label),
          subtitle: Text(
            defaultIceJson.isEmpty
                ? 'Enter server address to preview default STUN JSON'
                : defaultIceJson,
            style: AppTypography.caption.copyWith(color: AppColors.textFaint),
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
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _iceServersController,
          maxLines: 5,
          enabled: !_useDefaultIceForDomain,
          style: AppTypography.data,
          decoration: const InputDecoration(
            hintText:
                '[{"urls":"stun:your-domain-or-ip:3478"},'
                '{"urls":["turn:turn.example.com:3478?transport=udp"],'
                '"username":"user","credential":"pass"}]',
          ),
          onChanged: (_) => setState(() {
            _useDefaultIceForDomain = false;
          }),
        ),
      ],
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = (screen.width * _dialogWidthFraction)
        .clamp(_minDialogWidth, _maxDialogWidth);
    final dialogHeight = (screen.height * _dialogHeightFraction)
        .clamp(_minDialogHeight, _maxDialogHeight);

    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildNav(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: _buildContent(),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                      ),
                      child: const Text('CANCEL'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppButton(onPressed: _save, label: 'Save'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
