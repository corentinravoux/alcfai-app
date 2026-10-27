import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app_state.dart';
import 'core/alcf_cli.dart';
import 'core/guard.dart';
import 'core/launch.dart';
import 'core/profiles.dart';
import 'core/pty.dart';
import 'core/runner.dart';
import 'core/sandbox.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

void main() {
  final env = Platform.environment;
  final realHome = env['HOME']!;
  final sandbox = Sandbox(
      root: '$realHome/.local/share/alcfai/home', realHome: realHome);
  final alcfExe = whichOnPath('alcf-ai', env);
  final tokensExe = whichOnPath('alcf-tokens', env);

  final alcf = (alcfExe == null || tokensExe == null)
      ? null
      : AlcfCli(
          runner: const IoRunner(),
          sandbox: sandbox,
          guard: RealConfigGuard(RealConfigGuard.defaultPaths(realHome)),
          alcfExe: alcfExe,
          tokensExe: tokensExe,
          uvCacheDir: _uvCacheDir(env, realHome),
          sharedSettingsPath:
              '$realHome/Software/claude_config/claude/settings.json',
          parentEnv: env,
        );

  final defaultCwd = Directory('$realHome/Documents/Python').existsSync()
      ? '$realHome/Documents/Python'
      : realHome;

  final state = AppState(
    profiles: defaultProfiles(realHome),
    which: (exe) => whichOnPath(exe, env),
    sandbox: sandbox,
    alcf: alcf,
    start: startFlutterPty,
    parentEnv: env,
    defaultCwd: defaultCwd,
  );

  runApp(AlcfaiApp(state: state));
  sandbox.ensure().then((_) => state.refresh());
}

String _uvCacheDir(Map<String, String> env, String realHome) {
  final fromEnv = env['UV_CACHE_DIR'];
  if (fromEnv != null) return fromEnv;
  final uv = whichOnPath('uv', env);
  if (uv != null) {
    try {
      final r = Process.runSync(uv, ['cache', 'dir']);
      if (r.exitCode == 0) return '${r.stdout}'.trim();
    } on ProcessException {
      // fall through to the default
    }
  }
  return '$realHome/.cache/uv';
}

class AlcfaiApp extends StatelessWidget {
  const AlcfaiApp({super.key, required this.state, this.onConfigure});

  final AppState state;
  final ConfigureAction? onConfigure;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ALCF AI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: HomePage(state: state, onConfigure: onConfigure),
      );
}
