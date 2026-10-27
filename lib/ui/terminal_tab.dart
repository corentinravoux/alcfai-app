import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../core/launch.dart';
import '../core/pty.dart';
import 'theme.dart';

/// One running agent: a pseudo-terminal process drawn by xterm.
/// The process lives as long as the widget; hidden tabs keep running
/// because the home page keeps them in an IndexedStack.
class TerminalTab extends StatefulWidget {
  const TerminalTab({
    super.key,
    required this.spec,
    required this.start,
    required this.title,
    this.onExit,
  });

  final LaunchSpec spec;
  final PtyStarter start;
  final String title;
  final void Function(int code)? onExit;

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab>
    with AutomaticKeepAliveClientMixin {
  final terminal = Terminal(maxLines: 20000);
  late final PtySession _session;
  StreamSubscription<String>? _sub;
  bool _exited = false;

  @override
  void initState() {
    super.initState();
    _session = widget.start(widget.spec);
    _sub = _session.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);
    terminal.onOutput = (data) {
      if (!_exited) _session.write(utf8.encode(data));
    };
    terminal.onResize = (w, h, pw, ph) => _session.resize(h, w);
    _session.exitCode.then((code) {
      _exited = true;
      if (!mounted) return;
      terminal.write('\r\n[process exited with code $code]\r\n');
      widget.onExit?.call(code);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (!_exited) _session.kill();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TerminalView(
      terminal,
      autofocus: true,
      theme: terminalTheme,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
      textStyle: const TerminalStyle(fontFamily: Tok.mono, fontSize: 13.5),
    );
  }
}
