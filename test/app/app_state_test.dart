import 'dart:io';

import 'package:alcfai_app/app/app_state.dart';
import 'package:alcfai_app/core/alcf_cli.dart';
import 'package:alcfai_app/core/agents.dart';
import 'package:alcfai_app/core/app_store.dart';
import 'package:alcfai_app/core/guard.dart';
import 'package:alcfai_app/core/launch.dart';
import 'package:alcfai_app/core/profiles.dart';
import 'package:alcfai_app/core/runner.dart';
import 'package:alcfai_app/core/sandbox.dart';
import 'package:alcfai_app/core/term_tools.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_runner.dart';
import '../ui/terminal_tab_test.dart' show FakePty;

void main() {
  late Directory tmp;
  late String realHome;
  late Sandbox sb;
  late FakeRunner runner;
  late AppStore store;
  late List<LaunchSpec> started;

  AppState make({Set<String> missing = const {}}) {
    started = [];
    return AppState(
      profiles: defaultProfiles(
        realHome,
        accounts: [
          ClaudeAccount('claude-pro', 'Claude · Pro', '$realHome/.claude-alt'),
        ],
      ),
      which: (exe) => missing.contains(exe) ? null : '/bin/$exe',
      sandbox: sb,
      alcf: AlcfCli(
        runner: runner,
        sandbox: sb,
        guard: RealConfigGuard([]),
        alcfExe: '/bin/alcf-ai',
        tokensExe: '/bin/alcf-tokens',
        uvCacheDir: '/uv',
        sharedSettingsPath: '$realHome/shared.json',
        parentEnv: {'HOME': realHome, 'PATH': '/bin'},
      ),
      start: (spec) {
        started.add(spec);
        return FakePty();
      },
      parentEnv: {'HOME': realHome, 'PATH': '/bin'},
      defaultCwd: tmp.path,
      store: store,
    );
  }

  Profile p(AppState s, String id) => s.profiles.firstWhere((x) => x.id == id);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('alcfai_state_');
    realHome = '${tmp.path}/home';
    sb = Sandbox(
      root: '$realHome/.local/share/alcfai/home',
      realHome: realHome,
    );
    File('${sb.claudeDir}/settings.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '{"env": {"ANTHROPIC_BASE_URL": "https://x/resource_server/minerva/api", "ANTHROPIC_MODEL": "inkling-bf16"}}',
      );
    File('${sb.home}/.pi/agent/models.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '{"providers": {"alcf-inference-service-minerva-api": {"models": [{"id": "gpt-oss-120b"}]}}}',
      );
    runner = FakeRunner();
    store = AppStore('${tmp.path}/state.json');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('open pi passes the remembered model', () async {
    store.choices['pi-alcf'] = const AgentChoice('minerva', 'gpt-oss-120b');
    final s = make();
    await s.refresh();
    s.open(p(s, 'pi-alcf'), tmp.path);
    expect(s.tabs.single.spec.args, [
      '--model',
      'alcf-inference-service-minerva-api/gpt-oss-120b',
    ]);
  });

  test('open codex and opencode pass the remembered model', () async {
    File('${sb.home}/.codex/alcf-minerva-gpt-oss-120b.config.toml')
        .createSync(recursive: true);
    File('${sb.home}/.config/opencode/opencode.jsonc')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '{"provider": {"alcf-inference-service-minerva-api": {"models": {"gpt-oss-120b": {}}}}}',
      );
    const c = AgentChoice('minerva', 'gpt-oss-120b');
    store.choices['codex-alcf'] = c;
    store.choices['opencode-alcf'] = c;
    final s = make();
    await s.refresh();
    s.open(p(s, 'codex-alcf'), tmp.path);
    s.open(p(s, 'opencode-alcf'), tmp.path);
    expect(s.tabs[0].spec.args, [
      ...alcfCompatArgs(AgentKind.codex),
      '-p',
      'alcf-minerva-gpt-oss-120b',
    ]);
    expect(s.tabs[1].spec.args, [
      '--model',
      'alcf-inference-service-minerva-api/gpt-oss-120b',
    ]);
  });

  test('choiceFor claude falls back to the sandbox settings', () async {
    final s = make();
    expect(
      s.choiceFor(p(s, 'claude-alcf')),
      const AgentChoice('minerva', 'inkling-bf16'),
    );
    expect(s.choiceFor(p(s, 'pi-alcf')), isNull);
    expect(s.choiceFor(p(s, 'claude-pro')), isNull);
  });

  test('recordChoice persists to the store file', () async {
    final s = make();
    await s.recordChoice(p(s, 'pi-alcf'), const AgentChoice('sophia', 'm'));
    final again = AppStore(store.path);
    await again.load();
    expect(again.choices['pi-alcf'], const AgentChoice('sophia', 'm'));
  });

  test('open and close keep recent folders and last tabs saved', () async {
    final s = make();
    await s.refresh();
    s.open(p(s, 'pi-alcf'), '/w1');
    s.open(p(s, 'claude-pro'), '/w2');
    await s.saving;
    final a = AppStore(store.path);
    await a.load();
    expect(a.recentFolders, ['/w2', '/w1']);
    expect(a.lastTabs, [
      const SavedTab('pi-alcf', '/w1'),
      const SavedTab('claude-pro', '/w2'),
    ]);
    s.close(0);
    await s.saving;
    final b = AppStore(store.path);
    await b.load();
    expect(b.lastTabs, [const SavedTab('claude-pro', '/w2')]);
  });

  test('restart replaces an ended tab with a fresh session in place', () async {
    final s = make();
    await s.refresh();
    s.open(p(s, 'pi-alcf'), '/w1');
    s.open(p(s, 'claude-pro'), '/w2');
    final old = s.tabs[0];
    s.markExited(old, 1);
    s.restart(0);
    expect(s.tabs.length, 2);
    expect(s.tabs[0].id, isNot(old.id));
    expect(s.tabs[0].title, old.title);
    expect(s.tabs[0].spec.cwd, '/w1');
    expect(
      s.tabs[0].spec.env['ALCF_SESSION_ID'],
      isNot(old.spec.env['ALCF_SESSION_ID']),
    );
    expect(s.tabs[0].exitCode, isNull);
    expect(s.active, 0);
    expect(started.length, 0, reason: 'specs only; ptys start in widgets');
  });

  test(
    'reopenLast opens saved tabs that can open and skips the rest',
    () async {
      store.lastTabs = [
        SavedTab('pi-alcf', tmp.path),
        SavedTab('codex-alcf', tmp.path),
        const SavedTab('gone', '/'),
        SavedTab('claude-pro', '${tmp.path}/deleted-folder'),
      ];
      final s = make(missing: {'codex'});
      await s.refresh();
      expect(s.canReopen, 4);
      s.reopenLast();
      expect(s.tabs.map((t) => t.profile!.id), ['pi-alcf']);
      expect(s.canReopen, 0);
    },
  );

  test('zoom changes the font size and persists it', () async {
    final s = make();
    expect(s.fontSize, kTermFontSize);
    s.zoom(1);
    s.zoom(1);
    expect(s.fontSize, kTermFontSize + 2);
    s.zoom(0);
    expect(s.fontSize, kTermFontSize);
    s.zoom(-1);
    await s.saving;
    final a = AppStore(store.path);
    await a.load();
    expect(a.fontSize, kTermFontSize - 1);
  });

  test('statusFor reports the remembered model status', () async {
    runner.handlers['/bin/alcf-ai ls-jobs minerva'] = (_) =>
        const RunResult(0, "{'queued': [{'Models': 'inkling-bf16'}]}", '');
    final s = make();
    expect(await s.statusFor(p(s, 'claude-alcf')), ModelStatus.queued);
    expect(await s.statusFor(p(s, 'claude-pro')), isNull);
  });

  testWidgets('login is re-checked on a timer', (tester) async {
    var checks = 0;
    runner.handlers['/bin/alcf-tokens get-token'] = (_) {
      checks++;
      return const RunResult(0, '', '');
    };
    final s = make();
    s.startLoginChecks(const Duration(hours: 3));
    await tester.pump(const Duration(hours: 3));
    await tester.pump(const Duration(hours: 3));
    expect(checks, 2);
    s.dispose();
    await tester.pump(const Duration(hours: 3));
    expect(checks, 2);
  });

  group('split view', () {
    Future<AppState> three() async {
      final s = make();
      await s.refresh();
      for (final w in ['/a', '/b', '/c']) {
        s.open(p(s, 'pi-alcf'), w);
      }
      return s;
    }

    List<String?> shown(AppState s) => [
      for (final t in s.paneTabs) t?.spec.cwd,
    ];

    test('split shows a hidden tab on the right and focuses it', () async {
      final s = await three();
      expect(shown(s), ['/c']);
      s.toggleSplit();
      expect(s.isSplit, isTrue);
      expect(shown(s), ['/c', '/a']);
      expect(s.focus, 1);
      s.toggleSplit();
      expect(shown(s), ['/a'], reason: 'keeps the focused pane');
      expect(s.focus, 0);
    });

    test(
      'split with one tab leaves the new pane empty; open fills it',
      () async {
        final s = make();
        await s.refresh();
        s.open(p(s, 'pi-alcf'), '/a');
        s.toggleSplit();
        expect(shown(s), ['/a', null]);
        s.open(p(s, 'pi-alcf'), '/b');
        expect(shown(s), ['/a', '/b']);
      },
    );

    test('select focuses the pane already showing a tab, else uses the focused one', () async {
      final s = await three();
      s.toggleSplit(); // ['/c', '/a'], focus 1
      s.select(2); // '/c' is on the left
      expect(s.focus, 0);
      expect(shown(s), ['/c', '/a']);
      s.select(1); // '/b' hidden: goes to the focused (left) pane
      expect(shown(s), ['/b', '/a']);
      expect(s.active, 1);
    });

    test(
      'showInPane splits when dropped on the right; a shown tab swaps',
      () async {
        final s = await three();
        s.showInPane(1, 0); // drop '/a' on the right half
        expect(shown(s), ['/c', '/a']);
        expect(s.focus, 1);
        s.showInPane(0, 0); // drop '/a' on the left: swap
        expect(shown(s), ['/a', '/c']);
        expect(s.focus, 0);
      },
    );

    test(
      'closing a tab shows another hidden one, or collapses the empty pane',
      () async {
        final s = await three();
        s.toggleSplit(); // ['/c', '/a']
        s.close(0); // '/a' closes; '/b' is hidden and takes its place
        expect(shown(s), ['/c', '/b']);
        s.close(0); // '/b' closes; nothing hidden left
        expect(s.isSplit, isFalse);
        expect(shown(s), ['/c']);
        s.close(0);
        expect(shown(s), [null]);
      },
    );

    test('closePane keeps the other pane; restart stays in its pane', () async {
      final s = await three();
      s.toggleSplit(); // ['/c', '/a']
      s.markExited(s.tabs[0], 0);
      s.restart(0);
      expect(shown(s), ['/c', '/a']);
      expect(s.focus, 1);
      s.closePane(1);
      expect(shown(s), ['/c']);
      expect(s.tabs.length, 3, reason: 'tabs stay open');
    });
  });
}
