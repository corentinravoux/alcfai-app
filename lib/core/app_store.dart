import 'dart:convert';
import 'dart:io';

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
  AppStore(this.path);

  final String path;
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
      }),
    );
    await tmp.rename(path);
  }
}
