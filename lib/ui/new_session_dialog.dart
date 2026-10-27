import 'dart:io';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Asks for the working folder; returns it, or null when cancelled.
Future<String?> showNewSessionDialog(
    BuildContext context, String label, String defaultCwd) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NewSessionDialog(label: label, defaultCwd: defaultCwd),
  );
}

class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog({required this.label, required this.defaultCwd});
  final String label;
  final String defaultCwd;

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  late final _ctrl = TextEditingController(text: widget.defaultCwd);
  String? _error;

  void _start() {
    final path = _ctrl.text.trim();
    if (!Directory(path).existsSync()) {
      setState(() => _error = 'This folder does not exist.');
      return;
    }
    Navigator.pop(context, path);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('New ${widget.label} session',
          style: Theme.of(context).textTheme.titleMedium),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Working folder'),
            const SizedBox(height: 6),
            TextField(
              controller: _ctrl,
              autofocus: true,
              onSubmitted: (_) => _start(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(errorText: _error),
            ),
            const SizedBox(height: 6),
            Text('The agent starts in this folder and works on its files.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: Tok.muted),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _start, child: const Text('Start')),
      ],
    );
  }
}
