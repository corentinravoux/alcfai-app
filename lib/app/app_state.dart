import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/agents.dart';
import '../core/alcf_cli.dart';
import '../core/launch.dart';
import '../core/profiles.dart';
import '../core/pty.dart';
import '../core/sandbox.dart';

class ProfileStatus {
  const ProfileStatus(this.profile, this.exePath, this.configured);
  final Profile profile;
  final String? exePath;

  /// Native profiles are always configured.
  final bool configured;
  bool get installed => exePath != null;
}

class OpenTab {
  OpenTab({
    required this.id,
    required this.title,
    required this.profile,
    required this.spec,
    required this.route,
  });

  final int id;
  final String title;

  /// Null for the ALCF login tab.
  final Profile? profile;
  final LaunchSpec spec;

  /// Where requests go, shown above the terminal.
  final String route;
  int? exitCode;
}

class AppState extends ChangeNotifier {
  AppState({
    required this.profiles,
    required this.which,
    required this.sandbox,
    required this.alcf,
    required this.start,
    required this.parentEnv,
    required this.defaultCwd,
  });

  final List<Profile> profiles;
  final Which which;
  final Sandbox sandbox;

  /// Null when alcf-ai or alcf-tokens is missing: ALCF profiles are disabled.
  final AlcfCli? alcf;
  final PtyStarter start;
  final Map<String, String> parentEnv;
  String defaultCwd;

  List<ProfileStatus> statuses = [];
  final List<OpenTab> tabs = [];
  int active = 0;
  bool alcfLoggedIn = true;
  int _nextId = 0;

  bool get alcfAvailable => alcf != null;

  ProfileStatus statusOf(Profile p) =>
      statuses.firstWhere((s) => s.profile.id == p.id);

  Future<void> refresh() async {
    statuses = [
      for (final p in profiles)
        ProfileStatus(
          p,
          which(p.kind.exe),
          !p.isAlcf || sandbox.isConfigured(p.kind),
        ),
    ];
    alcfLoggedIn = alcf == null ? false : await alcf!.tokenOk();
    notifyListeners();
  }

  bool canOpen(ProfileStatus s) =>
      s.installed && s.configured && (!s.profile.isAlcf || alcfAvailable);

  void open(Profile p, String cwd) {
    final s = statusOf(p);
    final spec = buildLaunch(
      p,
      sandbox: sandbox,
      parentEnv: parentEnv,
      exePath: s.exePath!,
      cwd: cwd,
      sessionId: const Uuid().v4(),
    );
    final same = tabs.where((t) => t.profile?.id == p.id).length;
    _add(OpenTab(
      id: _nextId++,
      title: same == 0 ? p.label : '${p.label} (${same + 1})',
      profile: p,
      spec: spec,
      route: describeRoute(p),
    ));
    defaultCwd = cwd;
  }

  /// Opens a tab running `alcf-tokens login inference`.
  void openLogin() {
    final cli = alcf;
    if (cli == null) return;
    final cmd = cli.loginCommand;
    final env = {
      for (final e in parentEnv.entries)
        if (!kStrippedEnvKeys.contains(e.key) && !e.key.startsWith('ANTHROPIC_'))
          e.key: e.value,
    };
    _add(OpenTab(
      id: _nextId++,
      title: 'ALCF login',
      profile: null,
      spec: LaunchSpec(
          executable: cmd.first,
          args: cmd.sublist(1),
          env: env,
          cwd: sandbox.realHome),
      route: 'Signs you in to the ALCF inference service',
    ));
  }

  void _add(OpenTab t) {
    tabs.add(t);
    active = tabs.length - 1;
    notifyListeners();
  }

  void select(int i) {
    active = i;
    notifyListeners();
  }

  void close(int i) {
    tabs.removeAt(i);
    if (active >= tabs.length) active = tabs.isEmpty ? 0 : tabs.length - 1;
    notifyListeners();
  }

  void markExited(OpenTab t, int code) {
    t.exitCode = code;
    notifyListeners();
  }

  /// Plain sentence saying where a profile's requests go.
  String describeRoute(Profile p) {
    if (!p.isAlcf) {
      final account = p.id == 'claude-pro' ? 'Pro' : 'Team';
      return 'Anthropic, $account account (${_tilde(p.nativeConfigDir!)})';
    }
    if (p.kind == AgentKind.claude) {
      final env = _claudeEnv();
      final url = env['ANTHROPIC_BASE_URL'] ?? '';
      final cluster =
          RegExp(r'resource_server/([^/]+)/').firstMatch(url)?.group(1);
      final model = env['ANTHROPIC_MODEL'];
      if (cluster != null && model != null) {
        return 'ALCF $cluster, model $model';
      }
    }
    return 'ALCF, config in ${_tilde(sandbox.overrideValue(p.kind))}';
  }

  Map<String, dynamic> _claudeEnv() {
    try {
      final f = File('${sandbox.claudeDir}/settings.json');
      final v = jsonDecode(f.readAsStringSync());
      return (v is Map && v['env'] is Map)
          ? Map<String, dynamic>.from(v['env'] as Map)
          : {};
    } on Object {
      return {};
    }
  }

  String _tilde(String path) => path.startsWith(sandbox.realHome)
      ? '~${path.substring(sandbox.realHome.length)}'
      : path;
}
