import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';

import 'launch.dart';

/// The part of a pseudo-terminal process the UI needs; faked in tests.
abstract class PtySession {
  Stream<Uint8List> get output;
  Future<int> get exitCode;
  void write(Uint8List data);
  void resize(int rows, int cols);
  void kill();
}

typedef PtyStarter = PtySession Function(LaunchSpec spec);

/// flutter_pty copies only TERM, LANG, LOGNAME, USER, DISPLAY, LC_TYPE,
/// HOME and PATH from the app's own environment, then applies [LaunchSpec.env]
/// on top, so nothing else from the parent leaks into the agent.
PtySession startFlutterPty(LaunchSpec spec) => _FlutterPty(Pty.start(
      spec.executable,
      arguments: spec.args,
      workingDirectory: spec.cwd,
      environment: spec.env,
      rows: 40,
      columns: 120,
    ));

class _FlutterPty implements PtySession {
  _FlutterPty(this._pty);
  final Pty _pty;

  @override
  Stream<Uint8List> get output => _pty.output;
  @override
  Future<int> get exitCode => _pty.exitCode;
  @override
  void write(Uint8List data) => _pty.write(data);
  @override
  void resize(int rows, int cols) => _pty.resize(rows, cols);
  @override
  void kill() => _pty.kill();
}
