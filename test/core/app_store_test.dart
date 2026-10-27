import 'dart:io';

import 'package:alcfai_app/core/app_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('alcfai_store_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'round-trips choices, recent folders, last tabs and font size',
    () async {
      final path = '${tmp.path}/state.json';
      final a = AppStore(path)
        ..choices['pi-alcf'] = const AgentChoice('minerva', 'gpt-oss-120b')
        ..lastTabs = [const SavedTab('pi-alcf', '/w')]
        ..fontSize = 15.5;
      a.addRecent('/a');
      a.addRecent('/b');
      await a.save();

      final b = AppStore(path);
      await b.load();
      expect(
        b.choices['pi-alcf'],
        const AgentChoice('minerva', 'gpt-oss-120b'),
      );
      expect(b.recentFolders, ['/b', '/a']);
      expect(b.lastTabs, [const SavedTab('pi-alcf', '/w')]);
      expect(b.fontSize, 15.5);
    },
  );

  test('addRecent dedupes and keeps the 6 newest', () {
    final s = AppStore('${tmp.path}/x.json');
    for (final f in ['/1', '/2', '/3', '/4', '/5', '/6', '/7', '/3']) {
      s.addRecent(f);
    }
    expect(s.recentFolders, ['/3', '/7', '/6', '/5', '/4', '/2']);
  });

  test('load tolerates a missing or broken file', () async {
    final s = AppStore('${tmp.path}/missing.json');
    await s.load();
    expect(s.choices, isEmpty);
    File('${tmp.path}/bad.json').writeAsStringSync('{not json');
    final t = AppStore('${tmp.path}/bad.json');
    await t.load();
    expect(t.recentFolders, isEmpty);
    expect(t.fontSize, isNull);
  });
}
