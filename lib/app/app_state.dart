import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/agents.dart';
import '../core/alcf_cli.dart';
import '../core/app_store.dart';
import '../core/launch.dart';
import '../core/profiles.dart';
import '../core/pty.dart';
import '../core/sandbox.dart';
import '../core/term_tools.dart';

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
  bool get running => exitCode == null;
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
    required this.store,
  }) : _offer = List.of(store.lastTabs);

  final List<Profile> profiles;
  final Which which;
  final Sandbox sandbox;

  /// Null when alcf-ai or alcf-tokens is missing: ALCF profiles are disabled.
  final AlcfCli? alcf;
  final PtyStarter start;
  final Map<String, String> parentEnv;
  final AppStore store;
  String defaultCwd;

  List<ProfileStatus> statuses = [];
  final List<OpenTab> tabs = [];
  int active = 0;
  bool alcfLoggedIn = true;
  int _nextId = 0;

  /// Tabs from the previous run, offered once on the empty screen.
  List<SavedTab> _offer;
  Timer? _loginTimer;

  /// Completes when the last store write has finished.
  Future<void> saving = Future.value();

  bool get alcfAvailable => alcf != null;
  double get fontSize => store.fontSize ?? kTermFontSize;
  List<String> get recentFolders => store.recentFolders;
  int get canReopen => _offer.length;

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

  /// Re-checks the ALCF login regularly: access tokens last 48 h and the
  /// login itself 30 days, so it can lapse while the app stays open.
  void startLoginChecks([Duration every = const Duration(hours: 3)]) {
    _loginTimer?.cancel();
    _loginTimer = Timer.periodic(every, (_) => refresh());
  }

  @override
  void dispose() {
    _loginTimer?.cancel();
    super.dispose();
  }

  bool canOpen(ProfileStatus s) =>
      s.installed && s.configured && (!s.profile.isAlcf || alcfAvailable);

  /// Cluster and model for an ALCF profile: the one picked in Configure, or
  /// for Claude what alcf-ai wrote into the sandbox settings.
  AgentChoice? choiceFor(Profile p) {
    if (!p.isAlcf) return null;
    final saved = store.choices[p.id];
    if (saved != null) return saved;
    if (p.kind == AgentKind.claude) {
      final env = _claudeEnv();
      final cluster = RegExp(r'resource_server/([^/]+)/')
          .firstMatch('${env['ANTHROPIC_BASE_URL'] ?? ''}')
          ?.group(1);
      final model = env['ANTHROPIC_MODEL'];
      if (cluster != null && model is String) {
        return AgentChoice(cluster, model);
      }
    }
    return null;
  }

  Future<void> recordChoice(Profile p, AgentChoice c) {
    store.choices[p.id] = c;
    _save();
    notifyListeners();
    return saving;
  }

  /// Status of the profile's model on its cluster; null when unknown.
  Future<ModelStatus?> statusFor(Profile p) async {
    final c = choiceFor(p);
    final cli = alcf;
    if (c == null || cli == null) return null;
    return (await cli.modelStatus(c.cluster))[c.model];
  }

  OpenTab _makeTab(Profile p, String cwd, String title) {
    final s = statusOf(p);
    final spec = buildLaunch(
      p,
      sandbox: sandbox,
      parentEnv: parentEnv,
      exePath: s.exePath!,
      cwd: cwd,
      sessionId: const Uuid().v4(),
      args: p.isAlcf && p.kind == AgentKind.pi
          ? piModelArgs(sandbox, choiceFor(p))
          : const [],
    );
    return OpenTab(
      id: _nextId++,
      title: title,
      profile: p,
      spec: spec,
      route: describeRoute(p),
    );
  }

  void open(Profile p, String cwd) {
    final same = tabs.where((t) => t.profile?.id == p.id).length;
    final title = same == 0 ? p.label : '${p.label} (${same + 1})';
    _offer = [];
    defaultCwd = cwd;
    store.addRecent(cwd);
    _add(_makeTab(p, cwd, title));
  }

  /// Replaces tab [i] with a fresh session of the same agent and folder.
  void restart(int i) {
    final old = tabs[i];
    final p = old.profile;
    if (p == null) {
      tabs[i] = OpenTab(
        id: _nextId++,
        title: old.title,
        profile: null,
        spec: old.spec,
        route: old.route,
      );
    } else {
      tabs[i] = _makeTab(p, old.spec.cwd, old.title);
    }
    active = i;
    _save();
    notifyListeners();
  }

  /// Opens the tabs of the previous run whose agent can still start.
  void reopenLast() {
    final saved = _offer;
    _offer = [];
    for (final t in saved) {
      final p = profiles.where((x) => x.id == t.profileId).firstOrNull;
      if (p == null || !canOpen(statusOf(p))) continue;
      if (!Directory(t.cwd).existsSync()) continue;
      open(p, t.cwd);
    }
    notifyListeners();
  }

  /// Opens a tab running `alcf-tokens login inference`.
  void openLogin() {
    final cli = alcf;
    if (cli == null) return;
    final cmd = cli.loginCommand;
    final env = {
      for (final e in parentEnv.entries)
        if (!kStrippedEnvKeys.contains(e.key) &&
            !e.key.startsWith('ANTHROPIC_'))
          e.key: e.value,
    };
    _add(
      OpenTab(
        id: _nextId++,
        title: 'ALCF login',
        profile: null,
        spec: LaunchSpec(
          executable: cmd.first,
          args: cmd.sublist(1),
          env: env,
          cwd: sandbox.realHome,
        ),
        route: 'Signs you in to the ALCF inference service',
      ),
    );
  }

  void _add(OpenTab t) {
    tabs.add(t);
    active = tabs.length - 1;
    _save();
    notifyListeners();
  }

  void select(int i) {
    active = i;
    notifyListeners();
  }

  void close(int i) {
    tabs.removeAt(i);
    if (active >= tabs.length) active = tabs.isEmpty ? 0 : tabs.length - 1;
    _save();
    notifyListeners();
  }

  void markExited(OpenTab t, int code) {
    t.exitCode = code;
    notifyListeners();
  }

  /// step +1 / -1 zooms all terminals, 0 resets.
  void zoom(int step) {
    store.fontSize = zoomed(fontSize, step);
    _save();
    notifyListeners();
  }

  void _save() {
    store.lastTabs = [
      for (final t in tabs)
        if (t.profile != null) SavedTab(t.profile!.id, t.spec.cwd),
    ];
    saving = saving.then((_) => store.save()).catchError((_) {});
  }

  /// Plain sentence saying where a profile's requests go.
  String describeRoute(Profile p) {
    if (!p.isAlcf) {
      final account = p.id == 'claude-pro' ? 'Pro' : 'Team';
      return 'Anthropic, $account account (${_tilde(p.nativeConfigDir!)})';
    }
    final c = choiceFor(p);
    if (c != null) return 'ALCF ${c.cluster}, model ${c.model}';
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
