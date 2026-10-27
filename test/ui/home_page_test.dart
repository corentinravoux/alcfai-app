import 'dart:io';

import 'package:alcfai_app/app/app_state.dart';
import 'package:alcfai_app/core/alcf_cli.dart';
import 'package:alcfai_app/core/guard.dart';
import 'package:alcfai_app/core/launch.dart';
import 'package:alcfai_app/core/profiles.dart';
import 'package:alcfai_app/core/runner.dart';
import 'package:alcfai_app/core/sandbox.dart';
import 'package:alcfai_app/ui/home_page.dart';
import 'package:alcfai_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_runner.dart';
import 'terminal_tab_test.dart' show FakePty;

void main() {
  late Directory tmp;
  late String realHome;
  late Sandbox sb;
  late FakeRunner runner;
  late List<LaunchSpec> started;

  AppState makeState({
    Set<String> missing = const {'codex', 'opencode'},
    bool tokenOk = true,
  }) {
    runner = FakeRunner({
      '/bin/alcf-tokens get-token': (_) =>
          RunResult(tokenOk ? 0 : 1, '', ''),
    });
    started = [];
    return AppState(
      profiles: defaultProfiles(realHome),
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
    );
  }

  Future<AppState> pump(WidgetTester tester, AppState state) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.runAsync(state.refresh);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: HomePage(state: state),
    ));
    await tester.pump();
    return state;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('alcfai_home_');
    realHome = '${tmp.path}/home';
    Directory('$realHome/.globus').createSync(recursive: true);
    sb = Sandbox(root: '$realHome/.local/share/alcfai/home', realHome: realHome);
    // Claude and Pi already configured in the sandbox.
    File('${sb.claudeDir}/settings.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
          '{"env": {"ANTHROPIC_BASE_URL": "https://x/resource_server/minerva/api", "ANTHROPIC_MODEL": "inkling-bf16"}}');
    File('${sb.home}/.pi/agent/models.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"providers": {"alcf-inference-service-x": {}}}');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  IconButton button(WidgetTester t, String key) =>
      t.widget<IconButton>(find.byKey(ValueKey(key)));

  testWidgets('sidebar disables profiles whose binary is missing',
      (tester) async {
    await pump(tester, makeState());
    expect(find.text('Codex · ALCF'), findsOneWidget);
    expect(find.text('Not installed'), findsNWidgets(2));
    expect(button(tester, 'open-codex-alcf').onPressed, isNull);
    expect(button(tester, 'configure-codex-alcf').onPressed, isNull);
    expect(button(tester, 'open-pi-alcf').onPressed, isNotNull);
  });

  testWidgets('unconfigured ALCF profile offers Configure, not Open',
      (tester) async {
    File('${sb.home}/.pi/agent/models.json').deleteSync();
    await pump(tester, makeState());
    expect(find.byKey(const ValueKey('open-pi-alcf')), findsNothing);
    expect(find.byKey(const ValueKey('setup-pi-alcf')), findsOneWidget);
  });

  testWidgets('open adds a tab and selects it; close removes it',
      (tester) async {
    final state = await pump(tester, makeState());
    expect(find.text('Start a session'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-claude-alcf')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(state.tabs.length, 1);
    expect(state.active, 0);
    expect(started.single.env['CLAUDE_CONFIG_DIR'], sb.claudeDir);
    expect(find.textContaining('minerva'), findsWidgets);

    state.open(state.profiles.first, tmp.path);
    await tester.pump();
    expect(state.tabs.map((t) => t.title), ['Claude · ALCF', 'Claude · ALCF (2)']);
    expect(state.active, 1);

    await tester.tap(find.byKey(const ValueKey('close-tab-1')));
    await tester.pump();
    expect(state.tabs.length, 1);
    expect(state.active, 0);
  });

  testWidgets('login banner shows when the ALCF login is missing',
      (tester) async {
    final state = await pump(tester, makeState(tokenOk: false));
    expect(state.alcfLoggedIn, isFalse);
    expect(find.text('Log in'), findsOneWidget);
    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(started.single.executable, '/bin/alcf-tokens');
    expect(started.single.args, ['login', 'inference']);
  });

  testWidgets('shared-config hint shows when CLAUDE.md is not linked',
      (tester) async {
    await pump(tester, makeState());
    expect(
        find.text(
            'Run ~/Software/claude_config/install.sh --alcf to share CLAUDE.md, commands and skills'),
        findsOneWidget);
    expect(button(tester, 'open-claude-alcf').onPressed, isNotNull);
  });
}
