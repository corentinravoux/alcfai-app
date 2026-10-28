import 'dart:convert';
import 'dart:io';

import 'profiles.dart';

/// Cluster and model picked in Configure for one profile.
class AgentChoice {
  const AgentChoice(this.cluster, this.model);
  final String cluster;
  final String model;

  Map<String, String> toJson() => {'cluster': cluster, 'model': model};

  @override
  bool operator ==(Object other) =>
      other is AgentChoice && other.cluster == cluster && other.model == model;

  @override
  int get hashCode => Object.hash(cluster, model);

  @override
  String toString() => 'AgentChoice($cluster, $model)';
}

/// A tab to offer again on next start.
class SavedTab {
  const SavedTab(this.profileId, this.cwd);
  final String profileId;
  final String cwd;

  Map<String, String> toJson() => {'profile': profileId, 'cwd': cwd};

  @override
  bool operator ==(Object other) =>
      other is SavedTab && other.profileId == profileId && other.cwd == cwd;

  @override
  int get hashCode => Object.hash(profileId, cwd);
}

/// The app's own small state file (`~/.local/share/alcfai/state.json`).
/// Holds no secrets.
class AppStore {
  AppStore(this.path, {String? home})
    : home = home ?? Platform.environment['HOME'] ?? '';

  final String path;
  final String home;

  /// Claude accounts shown in the sidebar, when the user lists them (to
  /// name them, or to skip detection); null means detect them.
  List<ClaudeAccount>? accounts;
  final Map<String, AgentChoice> choices = {};
  List<String> recentFolders = [];
  List<SavedTab> lastTabs = [];
  double? fontSize;

  static const maxRecent = 6;

  void addRecent(String folder) {
    recentFolders = [
      folder,
      ...recentFolders.where((f) => f != folder),
    ].take(maxRecent).toList();
  }

  Future<void> load() async {
    final f = File(path);
    if (!await f.exists()) return;
    try {
      final v = jsonDecode(await f.readAsString());
      if (v is! Map) return;
      final c = v['choices'];
      if (c is Map) {
        c.forEach((k, e) {
          if (e is Map && e['cluster'] is String && e['model'] is String) {
            choices['$k'] = AgentChoice(e['cluster'], e['model']);
          }
        });
      }
      recentFolders = [
        for (final r in (v['recentFolders'] as List? ?? const []))
          if (r is String) r,
      ];
      lastTabs = [
        for (final t in (v['lastTabs'] as List? ?? const []))
          if (t is Map && t['profile'] is String && t['cwd'] is String)
            SavedTab(t['profile'], t['cwd']),
      ];
      final acc = v['accounts'];
      if (acc is List) {
        accounts = [
          for (final a in acc)
            if (a is Map &&
                a['id'] is String &&
                a['label'] is String &&
                a['dir'] is String)
              ClaudeAccount(
                a['id'],
                a['label'],
                (a['dir'] as String).startsWith('~/')
                    ? '$home${(a['dir'] as String).substring(1)}'
                    : a['dir'],
              ),
        ];
      }
      final fs = v['fontSize'];
      fontSize = fs is num ? fs.toDouble() : null;
    } on Object {
      // A broken file is ignored and rewritten on the next save.
    }
  }

  Future<void> save() async {
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'choices': {for (final e in choices.entries) e.key: e.value.toJson()},
        'recentFolders': recentFolders,
        'lastTabs': [for (final t in lastTabs) t.toJson()],
        'fontSize': ?fontSize,
        if (accounts != null)
          'accounts': [
            for (final a in accounts!)
              {'id': a.id, 'label': a.label, 'dir': _tilde(a.dir)},
          ],
      }),
    );
    await tmp.rename(path);
  }

  String _tilde(String dir) => home.isNotEmpty && dir.startsWith('$home/')
      ? '~${dir.substring(home.length)}'
      : dir;
}
