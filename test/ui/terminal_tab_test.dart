import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alcfai_app/core/launch.dart';
import 'package:alcfai_app/core/pty.dart';
import 'package:alcfai_app/ui/terminal_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

class FakePty implements PtySession {
  final out = StreamController<Uint8List>();
  final exit = Completer<int>();
  final written = <String>[];
  bool killed = false;

  @override
  Stream<Uint8List> get output => out.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  void write(Uint8List data) => written.add(utf8.decode(data));
  @override
  void resize(int rows, int cols) {}
  @override
  void kill() => killed = true;
}

const spec = LaunchSpec(executable: '/bin/pi', args: [], env: {}, cwd: '/w');

void main() {
  late FakePty pty;

  Future<Terminal> pump(WidgetTester tester) async {
    pty = FakePty();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TerminalTab(spec: spec, start: (_) => pty, title: 'Pi · ALCF'),
      ),
    ));
    return tester.widget<TerminalView>(find.byType(TerminalView)).terminal;
  }

  testWidgets('terminal tab shows exit code', (tester) async {
    final term = await pump(tester);
    pty.out.add(Uint8List.fromList(utf8.encode('hello')));
    await tester.pump();
    pty.exit.complete(3);
    await tester.pump();
    final text = term.buffer.getText();
    expect(text, contains('hello'));
    expect(text, contains('[process exited with code 3]'));
  });

  testWidgets('typing is forwarded', (tester) async {
    final term = await pump(tester);
    term.textInput('x');
    expect(pty.written, ['x']);
  });

  testWidgets('dispose kills the process', (tester) async {
    await pump(tester);
    await tester.pumpWidget(const SizedBox());
    expect(pty.killed, isTrue);
  });
}
