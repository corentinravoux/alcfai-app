import 'dart:io';

import 'package:alcfai_app/core/agents.dart';
import 'package:alcfai_app/core/app_store.dart';
import 'package:alcfai_app/core/launch.dart';
import 'package:alcfai_app/core/profiles.dart';
import 'package:alcfai_app/core/sandbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sb = Sandbox(root: '/h/.local/share/alcfai/home', realHome: '/h');
  final profiles = {for (final p in defaultProfiles('/h')) p.id: p};
  const parentEnv = {
    'CLAUDE_CONFIG_DIR': '/x/.claude-alt',
    'ANTHROPIC_API_KEY': 'k',
    'ANTHROPIC_BASE_URL': 'u',
    'CLAUDE_CODE_OAUTH_TOKEN': 't',
    'PATH': '/bin',
    'HOME': '/h',
  };

  LaunchSpec launch(String id, {String cwd = '/w'}) => buildLaunch(
        profiles[id]!,
        sandbox: sb,
        parentEnv: parentEnv,
        exePath: '/bin/${profiles[id]!.kind.exe}',
        cwd: cwd,
        sessionId: 'sid',
      );

  test('defaultProfiles ids and labels', () {
    expect(defaultProfiles('/h').map((p) => '${p.id}|${p.label}'), [
      'claude-alcf|Claude · ALCF',
      'pi-alcf|Pi · ALCF',
      'codex-alcf|Codex · ALCF',
      'opencode-alcf|OpenCode · ALCF',
      'claude-pro|Claude · Pro',
      'claude-team|Claude · Team',
    ]);
    expect(profiles['claude-pro']!.nativeConfigDir, '/h/.claude-alt');
    expect(profiles['claude-team']!.nativeConfigDir, '/h/.claude');
  });

  test('buildLaunch strips inherited agent env', () {
    final s = launch('claude-alcf');
    expect(s.env['CLAUDE_CONFIG_DIR'], sb.claudeDir);
    expect(s.env.keys.where((k) => k.startsWith('ANTHROPIC_')), isEmpty);
    expect(s.env.containsKey('CLAUDE_CODE_OAUTH_TOKEN'), isFalse);
    expect(s.env['PATH'], '/bin');
    expect(s.env['HOME'], '/h');
    expect(s.executable, '/bin/claude');
  });

  test('native profiles point at their own dir and never at ALCF', () {
    final pro = launch('claude-pro');
    final team = launch('claude-team');
    expect(pro.env['CLAUDE_CONFIG_DIR'], '/h/.claude-alt');
    expect(team.env['CLAUDE_CONFIG_DIR'], '/h/.claude');
    for (final s in [pro, team]) {
      expect(s.env.containsKey('ALCF_SESSION_ID'), isFalse);
      expect(s.env.keys.where((k) => k.startsWith('ANTHROPIC_')), isEmpty);
    }
  });

  test('alcf profiles set override and session id', () {
    final cases = {
      'pi-alcf': ('PI_CODING_AGENT_DIR', AgentKind.pi),
      'codex-alcf': ('CODEX_HOME', AgentKind.codex),
      'opencode-alcf': ('OPENCODE_CONFIG', AgentKind.opencode),
    };
    cases.forEach((id, c) {
      final s = launch(id);
      expect(s.env[c.$1], sb.overrideValue(c.$2), reason: id);
      expect(s.env['ALCF_SESSION_ID'], 'sid', reason: id);
      expect(s.env.containsKey('CLAUDE_CONFIG_DIR'), isFalse, reason: id);
    });
    expect(launch('claude-alcf').env['ALCF_SESSION_ID'], 'sid');
  });

  test('cwd and args passed through', () {
    final s = launch('pi-alcf', cwd: '/w/my project');
    expect(s.cwd, '/w/my project');
    expect(s.args, isEmpty);
  });

  test('whichOnPath finds executables only', () {
    final tmp = Directory.systemTemp.createTempSync('alcfai_which_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final a = Directory('${tmp.path}/a')..createSync();
    final b = Directory('${tmp.path}/b')..createSync();
    final exe = File('${b.path}/tool')..writeAsStringSync('#!/bin/sh\n');
    Process.runSync('chmod', ['+x', exe.path]);
    File('${a.path}/plain').writeAsStringSync('x');
    final env = {'PATH': '${a.path}:${b.path}'};
    expect(whichOnPath('tool', env), exe.path);
    expect(whichOnPath('plain', env), isNull);
    expect(whichOnPath('missing', env), isNull);
  });

  test('piModelArgs picks the provider that serves the chosen model', () {
    final tmp = Directory.systemTemp.createTempSync('alcfai_pi_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final box = Sandbox(root: '${tmp.path}/home', realHome: tmp.path);
    File('${box.home}/.pi/agent/models.json')
      ..createSync(recursive: true)
      ..writeAsStringSync("""
{"providers": {
  "alcf-inference-service-sophia-vllm": {"models": [{"id": "openai/gpt-oss-120b"}]},
  "alcf-inference-service-minerva-api": {"models": [{"id": "gpt-oss-120b"}, {"id": "inkling-bf16"}]}
}}""");
    expect(piModelArgs(box, const AgentChoice('minerva', 'inkling-bf16')),
        ['--model', 'alcf-inference-service-minerva-api/inkling-bf16']);
    expect(piModelArgs(box, const AgentChoice('sophia', 'openai/gpt-oss-120b')),
        ['--model', 'alcf-inference-service-sophia-vllm/openai/gpt-oss-120b']);
    expect(piModelArgs(box, const AgentChoice('tara', 'x')), isEmpty);
    expect(piModelArgs(box, null), isEmpty);
  });
}
