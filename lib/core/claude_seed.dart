import 'dart:convert';
import 'dart:io';

/// Keys copied from the shared claude_config settings into the ALCF Claude.
const kSeedKeys = ['outputStyle', 'theme', 'permissions', 'statusLine'];

/// Keys copied only when "Include plugins & hooks" is on.
const kPluginKeys = ['hooks', 'enabledPlugins', 'extraKnownMarketplaces'];

/// Keys alcf-ai writes; kept across re-seeds so ALCF keeps working.
const kAlcfKeys = ['env', 'apiKeyHelper'];

Map<String, dynamic> buildClaudeSeed(
  Map<String, dynamic> shared, {
  required bool includePlugins,
}) {
  final keys = [...kSeedKeys, if (includePlugins) ...kPluginKeys];
  return {
    for (final k in keys)
      if (shared.containsKey(k)) k: shared[k],
  };
}

/// Rebuilds the sandbox settings.json from the shared one.
///
/// The sandbox file is always a real file: a symlink there is removed, never
/// written through, so the shared file cannot change.
Future<void> writeClaudeSeed({
  required String sharedSettingsPath,
  required String sandboxSettingsPath,
  required bool includePlugins,
}) async {
  final shared = await _readJson(sharedSettingsPath);
  final seed = buildClaudeSeed(shared, includePlugins: includePlugins);

  if (FileSystemEntity.isLinkSync(sandboxSettingsPath)) {
    await Link(sandboxSettingsPath).delete();
  }
  final existing = await _readJson(sandboxSettingsPath);
  for (final k in kAlcfKeys) {
    if (existing.containsKey(k)) seed[k] = existing[k];
  }

  final target = File(sandboxSettingsPath);
  await target.parent.create(recursive: true);
  final tmp = File('${target.parent.path}/.settings.json.tmp');
  await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(seed));
  await tmp.rename(target.path);
}

Future<Map<String, dynamic>> _readJson(String path) async {
  final f = File(path);
  if (!await f.exists()) return {};
  final v = jsonDecode(await f.readAsString());
  return v is Map<String, dynamic> ? v : {};
}
