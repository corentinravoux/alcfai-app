import 'dart:io';

import 'agents.dart';
import 'profiles.dart';
import 'sandbox.dart';

typedef Which = String? Function(String exe);

/// Removed from the parent environment before every launch, together with
/// every `ANTHROPIC_*` key, so no tab inherits another account's routing.
const kStrippedEnvKeys = [
  'CLAUDE_CONFIG_DIR',
  'CODEX_HOME',
  'PI_CODING_AGENT_DIR',
  'OPENCODE_CONFIG',
  'CLAUDE_CODE_OAUTH_TOKEN',
  'ALCF_SESSION_ID',
];

class LaunchSpec {
  const LaunchSpec({
    required this.executable,
    required this.args,
    required this.env,
    required this.cwd,
  });

  final String executable;
  final List<String> args;

  /// The complete environment of the child (not merged with the parent).
  final Map<String, String> env;
  final String cwd;
}

String? whichOnPath(String exe, Map<String, String> env) {
  for (final dir in (env['PATH'] ?? '').split(':')) {
    if (dir.isEmpty) continue;
    final f = File('$dir/$exe');
    if (f.existsSync() && f.statSync().mode & 0x49 != 0) return f.path;
  }
  return null;
}

LaunchSpec buildLaunch(
  Profile p, {
  required Sandbox sandbox,
  required Map<String, String> parentEnv,
  required String exePath,
  required String cwd,
  required String sessionId,
  List<String> args = const [],
}) {
  final env = {
    for (final e in parentEnv.entries)
      if (!kStrippedEnvKeys.contains(e.key) && !e.key.startsWith('ANTHROPIC_'))
        e.key: e.value,
  };
  if (p.isAlcf) {
    env['ALCF_SESSION_ID'] = sessionId;
    final key = switch (p.kind) {
      AgentKind.claude => 'CLAUDE_CONFIG_DIR',
      AgentKind.codex => 'CODEX_HOME',
      AgentKind.pi => 'PI_CODING_AGENT_DIR',
      AgentKind.opencode => 'OPENCODE_CONFIG',
    };
    env[key] = sandbox.overrideValue(p.kind);
  } else {
    env['CLAUDE_CONFIG_DIR'] = p.nativeConfigDir!;
  }
  env['TERM'] = 'xterm-256color';
  return LaunchSpec(executable: exePath, args: args, env: env, cwd: cwd);
}
