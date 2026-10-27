import 'dart:io';

import 'package:crypto/crypto.dart';

/// Hashes the user's real agent config files so the app can prove a
/// configure run left them untouched.
class RealConfigGuard {
  RealConfigGuard(this.paths);

  final List<String> paths;

  static List<String> defaultPaths(String realHome) => [
    '$realHome/Software/claude_config/claude/settings.json',
    '$realHome/.claude/settings.json',
    '$realHome/.claude-alt/settings.json',
    '$realHome/.codex/config.toml',
    '$realHome/.pi/agent/models.json',
    '$realHome/.config/opencode/opencode.jsonc',
  ];

  /// sha256 per path (through symlinks); null for a missing file.
  Future<Map<String, String?>> snapshot() async => {
    for (final path in paths) path: await _hash(path),
  };

  /// Paths whose content, existence or absence changed since [before].
  Future<List<String>> changedSince(Map<String, String?> before) async {
    final now = await snapshot();
    return [
      for (final path in paths)
        if (now[path] != before[path]) path,
    ];
  }

  static Future<String?> _hash(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return sha256.convert(await f.readAsBytes()).toString();
  }
}
