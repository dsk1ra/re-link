import 'package:flutter/material.dart';
import 'package:application/src/features/settings/data/local_settings.dart';

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
    _controller = TextEditingController(text: widget.settings.getDomain());
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
        Navigator.pop(context, widget.settings.getDomain());
        widget.onDomainChanged?.call(widget.settings.getDomain());
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
    return AlertDialog(
      title: const Text('Change Server Address'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the address of your signaling server:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
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
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text(
              'Examples:\n'
              '• localhost:8080 (local development)\n'
              '• example.com (production)\n'
              '• relay.example.com:8443 (custom port)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveDomain,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFcc3f0c),
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
