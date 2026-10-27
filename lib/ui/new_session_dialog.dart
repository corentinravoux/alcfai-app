import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

typedef PickFolder = Future<String?> Function();

Future<String?> pickFolderWithPortal() => getDirectoryPath();

/// Asks for the working folder; returns it, or null when cancelled.
Future<String?> showNewSessionDialog(
  BuildContext context,
  String label,
  String defaultCwd, {
  List<String> recent = const [],
  String? warning,
  PickFolder? pickFolder,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NewSessionDialog(
      label: label,
      defaultCwd: defaultCwd,
      recent: recent,
      warning: warning,
      pickFolder: pickFolder ?? pickFolderWithPortal,
    ),
  );
}

class _NewSessionDialog extends StatefulWidget {
  const _NewSessionDialog({
    required this.label,
    required this.defaultCwd,
    required this.recent,
    required this.warning,
    required this.pickFolder,
  });
  final String label;
  final String defaultCwd;
  final List<String> recent;
  final String? warning;
  final PickFolder pickFolder;

  @override
  State<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends State<_NewSessionDialog> {
  late final _ctrl = TextEditingController(text: widget.defaultCwd);
  String? _error;

  void _set(String path) => setState(() {
    _ctrl.text = path;
    _error = null;
  });

  Future<void> _browse() async {
    final p = await widget.pickFolder();
    if (p != null && mounted) _set(p);
  }

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
    final t = Theme.of(context).textTheme;
    final recent = widget.recent
        .where((r) => Directory(r).existsSync())
        .toList(growable: false);
    return AlertDialog(
      title: Text('New ${widget.label} session', style: t.titleMedium),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.warning != null) ...[
              Text(
                widget.warning!,
                style: t.bodyMedium?.copyWith(color: Tok.queued),
              ),
              const SizedBox(height: 14),
            ],
            const Text('Working folder'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    onSubmitted: (_) => _start(),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(errorText: _error),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _browse, child: const Text('Browse')),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'The agent starts in this folder and works on its files.',
              style: t.bodySmall,
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Recent folders',
                style: t.bodySmall?.copyWith(
                  color: Tok.faint,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < recent.length; i++)
                InkWell(
                  key: ValueKey('recent-$i'),
                  borderRadius: BorderRadius.circular(Tok.radius),
                  hoverColor: Tok.raised,
                  onTap: () => _set(recent[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 6,
                    ),
                    child: Text(
                      recent[i],
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                ),
            ],
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
