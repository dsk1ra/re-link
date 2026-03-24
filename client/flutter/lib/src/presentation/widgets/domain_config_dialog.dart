import 'package:flutter/material.dart';
import 'package:application/src/features/settings/data/local_settings.dart';
import 'package:application/src/presentation/ui/ui_config.dart';

/// Dialog for changing the signaling server domain
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
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.settings.getDomain() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveDomain() async {
    final domain = _controller.text.trim();
    if (domain.isEmpty) {
      _showError('Please enter a domain or server address');
      return;
    }

    try {
      await widget.settings.setDomain(domain);
      if (mounted) {
        final updatedDomain = widget.settings.getDomain() ?? domain;
        Navigator.pop(context, updatedDomain);
        widget.onDomainChanged?.call(updatedDomain);
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
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text(
        'Change Server Address',
        style: TextStyle(color: AppColors.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the address of your signaling server:',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              cursorColor: AppColors.primary,
              style: const TextStyle(color: AppColors.textMuted),
              decoration: InputDecoration(
                hintText: 'https://your-domain.com or localhost:8080',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.outline),
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
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text(
              'Examples:\n'
              '• localhost:8080 (local development)\n'
              '• https://example.com (production)\n'
              '• relay.example.com:8443 (custom port)',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveDomain,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
