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

  /// The view shows one pane, or two side by side. Each pane shows one
  /// tab (by id), or nothing (an empty pane waiting for a session).
  /// Every tab keeps running whether shown or not.
  List<int?> _panes = [null];

  /// The pane that receives tab clicks and new sessions.
  int focus = 0;

  bool get isSplit => _panes.length == 2;

  List<OpenTab?> get paneTabs => [for (final id in _panes) _byId(id)];

  /// Index of the tab in the focused pane (0 when it is empty).
  int get active {
    final i = tabs.indexWhere((t) => t.id == _panes[focus]);
    return i < 0 ? 0 : i;
  }

  /// The pane showing tab [i], or null when it is hidden.
  int? paneOf(int i) {
    final p = _panes.indexOf(tabs[i].id);
    return p < 0 ? null : p;
  }

  OpenTab? _byId(int? id) =>
      id == null ? null : tabs.where((t) => t.id == id).firstOrNull;

  /// The first tab no pane shows, preferring index [from] then earlier ones.
  int? _hiddenFrom(int from) {
    final order = [
      for (var i = from; i < tabs.length; i++) i,
      for (var i = from - 1; i >= 0; i--) i,
    ];
    for (final i in order) {
      if (i >= 0 && !_panes.contains(tabs[i].id)) return tabs[i].id;
    }
    return null;
  }

  /// Splits the view (the new right pane shows a hidden tab, or nothing,
  /// and takes the focus), or goes back to one pane, keeping the focused one.
  void toggleSplit() {
    if (isSplit) {
      closePane(1 - focus);
      return;
    }
    _panes = [_panes[0], _hiddenFrom(0)];
    focus = 1;
    notifyListeners();
  }

  /// Removes pane [pane]; its tab keeps running, hidden.
  void closePane(int pane) {
    if (!isSplit) return;
    _panes = [_panes[1 - pane]];
    focus = 0;
    notifyListeners();
  }

  void focusPane(int pane) {
    if (pane == focus || pane >= _panes.length) return;
    focus = pane;
    notifyListeners();
  }

  /// Shows tab [i] in pane [pane] (dropping a tab there). Pane 1 of a
  /// single view splits it. A tab already shown in the other pane swaps
  /// places with this pane's tab.
  void showInPane(int pane, int i) {
    final id = tabs[i].id;
    if (pane >= _panes.length) _panes = [_panes[0], null];
    final other = _panes.indexOf(id);
    if (other >= 0 && other != pane) _panes[other] = _panes[pane];
    _panes[pane] = id;
    focus = pane;
    _dropEmptyPane();
    notifyListeners();
  }

  /// A split view never keeps an empty pane once a tab has gone.
  void _dropEmptyPane() {
    if (!isSplit || !_panes.contains(null)) return;
    final keep = _panes.indexWhere((id) => id != null);
    if (keep < 0) return;
    _panes = [_panes[keep]];
    focus = 0;
  }

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
      args: p.isAlcf
          ? [
              ...alcfCompatArgs(p.kind),
              ...modelArgs(p.kind, sandbox, choiceFor(p)),
            ]
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
    final pane = _panes.indexOf(old.id);
    if (pane >= 0) {
      _panes[pane] = tabs[i].id;
      focus = pane;
    } else {
      _panes[focus] = tabs[i].id;
    }
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
    _panes[focus] = t.id;
    _save();
    notifyListeners();
  }

  /// Shows tab [i]: focuses the pane already showing it, else puts it in
  /// the focused pane.
  void select(int i) {
    final pane = _panes.indexOf(tabs[i].id);
    if (pane >= 0) {
      focus = pane;
    } else {
      _panes[focus] = tabs[i].id;
    }
    notifyListeners();
  }

  void close(int i) {
    final id = tabs.removeAt(i).id;
    for (var p = 0; p < _panes.length; p++) {
      if (_panes[p] == id) _panes[p] = _hiddenFrom(i);
    }
    if (tabs.isEmpty) {
      _panes = [null];
      focus = 0;
    } else if (isSplit && _panes.contains(null)) {
      _dropEmptyPane();
    }
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
      return 'Anthropic, account in ${_tilde(p.nativeConfigDir!)}';
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
