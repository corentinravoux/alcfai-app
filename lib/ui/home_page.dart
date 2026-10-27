import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../core/profiles.dart';
import 'new_session_dialog.dart';
import 'sidebar.dart';
import 'terminal_tab.dart';
import 'theme.dart';

typedef ConfigureAction = Future<void> Function(
    BuildContext context, AppState state, Profile profile);

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state, this.onConfigure});

  final AppState state;
  final ConfigureAction? onConfigure;

  Future<void> _open(BuildContext context, ProfileStatus s) async {
    final cwd =
        await showNewSessionDialog(context, s.profile.label, state.defaultCwd);
    if (cwd != null) state.open(s.profile, cwd);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        body: Row(
          children: [
            Sidebar(
              state: state,
              onOpen: (s) => _open(context, s),
              onConfigure: (s) =>
                  onConfigure?.call(context, state, s.profile),
            ),
            Expanded(
              child: Column(
                children: [
                  _Banner(state: state),
                  if (state.tabs.isEmpty)
                    const Expanded(child: _EmptyState())
                  else ...[
                    _TabStrip(state: state),
                    _RouteBar(tab: state.tabs[state.active]),
                    Expanded(
                      child: IndexedStack(
                        index: state.active,
                        children: [
                          for (final t in state.tabs)
                            TerminalTab(
                              key: ValueKey(t.id),
                              spec: t.spec,
                              start: state.start,
                              title: t.title,
                              onExit: (code) => state.markExited(t, code),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final String text;
    Widget? action;
    if (!state.alcfAvailable) {
      text = 'ALCF agents need alcf-ai and alcf-tokens. Install them with '
          'uv tool install alcf-ai and uv tool install alcf-tokens, then restart.';
    } else if (!state.alcfLoggedIn) {
      text = 'You are not signed in to ALCF. ALCF agents need a login, '
          'which lasts 30 days.';
      action = FilledButton(
          onPressed: state.openLogin, child: const Text('Log in'));
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Tok.raised,
        border: Border(bottom: BorderSide(color: Tok.line)),
      ),
      child: Row(children: [
        Expanded(child: Text(text)),
        if (action != null) ...[const SizedBox(width: 12), action],
        if (state.alcfAvailable) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Check again',
            onPressed: state.refresh,
            icon: const Icon(Icons.refresh_rounded, size: 18, color: Tok.muted),
          ),
        ],
      ]),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Tok.rail,
        border: Border(bottom: BorderSide(color: Tok.line)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < state.tabs.length; i++)
            _TabChip(state: state, index: i),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.state, required this.index});
  final AppState state;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = state.tabs[index];
    final active = index == state.active;
    final exited = t.exitCode != null;
    return InkWell(
      onTap: () => state.select(index),
      hoverColor: Tok.raised,
      child: Container(
        padding: const EdgeInsets.only(left: 14, right: 2),
        decoration: BoxDecoration(
          color: active ? Tok.bg : Colors.transparent,
          border: Border(
            bottom: BorderSide(
                color: active ? Tok.accent : Colors.transparent, width: 2),
            right: const BorderSide(color: Tok.line),
          ),
        ),
        child: Row(children: [
          Text(
            exited ? '${t.title} (ended)' : t.title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: exited ? Tok.faint : (active ? Tok.text : Tok.muted),
            ),
          ),
          IconButton(
            key: ValueKey('close-tab-$index'),
            tooltip: 'Close session',
            visualDensity: VisualDensity.compact,
            onPressed: () => state.close(index),
            icon: const Icon(Icons.close_rounded, size: 15, color: Tok.faint),
          ),
        ]),
      ),
    );
  }
}

/// Says where this session's requests go. The one place the app spends
/// visual weight: running on the wrong backend is the failure this app
/// exists to prevent.
class _RouteBar extends StatelessWidget {
  const _RouteBar({required this.tab});
  final OpenTab tab;

  @override
  Widget build(BuildContext context) {
    final alcf = tab.profile?.isAlcf ?? true;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Tok.bg,
        border: Border(bottom: BorderSide(color: Tok.line)),
      ),
      child: Row(children: [
        Container(
          width: 3,
          height: 14,
          color: alcf ? Tok.accent : Tok.muted,
        ),
        const SizedBox(width: 10),
        Text('Runs on ',
            style: Theme.of(context).textTheme.bodySmall),
        Flexible(
          child: Text(tab.route,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: Tok.text)),
        ),
        const Spacer(),
        Flexible(
          child: Text('in ${tab.spec.cwd}',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Align(
      alignment: const Alignment(-0.6, -0.5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start a session',
                style: t.titleMedium?.copyWith(fontSize: 22)),
            const SizedBox(height: 10),
            Text(
              'Pick an agent on the left. Each session runs in its own tab, '
              'and the others keep running while you switch.',
              style: t.bodyMedium?.copyWith(color: Tok.muted, height: 1.5),
            ),
            const SizedBox(height: 10),
            Text(
              'ALCF agents read their settings from the app folder, so your '
              'own Claude setup stays as it is.',
              style: t.bodyMedium?.copyWith(color: Tok.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
