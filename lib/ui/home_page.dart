import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../core/alcf_cli.dart';
import '../core/profiles.dart';
import 'new_session_dialog.dart';
import 'sidebar.dart';
import 'terminal_tab.dart';
import 'theme.dart';

typedef ConfigureAction = Future<void> Function(
  BuildContext context,
  AppState state,
  Profile profile,
);

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.state,
    this.onConfigure,
    this.pickFolder,
  });

  final AppState state;
  final ConfigureAction? onConfigure;
  final PickFolder? pickFolder;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppState get state => widget.state;

  /// Share of the width given to the left pane.
  double _ratio = 0.5;

  /// True while a tab is being dragged: the panes then show drop zones.
  bool _dragging = false;

  void _setDragging(bool v) {
    if (v != _dragging) setState(() => _dragging = v);
  }

  Future<void> _open(BuildContext context, ProfileStatus s) async {
    final p = s.profile;
    String? warning;
    final status = await state.statusFor(p);
    final c = state.choiceFor(p);
    if (c != null && status == ModelStatus.queued) {
      warning =
          '${c.model} is queued on ${c.cluster}. The first answer can '
          'take several minutes while it loads.';
    } else if (c != null && status == ModelStatus.offline) {
      warning =
          '${c.model} is not loaded on ${c.cluster}. ALCF starts it on '
          'the first request, which can take several minutes.';
    }
    if (!context.mounted) return;
    final cwd = await showNewSessionDialog(
      context,
      p.label,
      state.defaultCwd,
      recent: state.recentFolders,
      warning: warning,
      pickFolder: widget.pickFolder,
    );
    if (cwd != null) state.open(p, cwd);
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
                  widget.onConfigure?.call(context, state, s.profile),
            ),
            Expanded(
              child: Column(
                children: [
                  _Banner(state: state),
                  if (state.tabs.isEmpty)
                    Expanded(child: _EmptyState(state: state))
                  else ...[
                    _TabStrip(state: state, onDragging: _setDragging),
                    Expanded(child: _panesView()),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _divider = 7.0;
  static const _routeBar = 30.0;

  /// The panes side by side. Every terminal lives in one Stack, placed over
  /// the pane that shows it (or hidden behind the first one), so moving a
  /// tab between panes never restarts its process.
  Widget _panesView() {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final panes = <Rect>[
          if (!state.isSplit)
            Rect.fromLTWH(0, 0, w, h)
          else ...[
            Rect.fromLTWH(0, 0, (w - _divider) * _ratio, h),
            Rect.fromLTRB((w - _divider) * _ratio + _divider, 0, w, h),
          ],
        ];
        Rect body(Rect r) =>
            Rect.fromLTRB(r.left, r.top + _routeBar, r.right, r.bottom);
        final shown = state.paneTabs;
        return Stack(
          children: [
            for (var i = 0; i < state.tabs.length; i++)
              _terminal(i, panes, body),
            for (var p = 0; p < panes.length; p++)
              if (shown[p] == null)
                Positioned.fromRect(
                  key: ValueKey('empty-pane-$p'),
                  rect: panes[p],
                  child: _EmptyPane(
                    focused: state.focus == p,
                    onTap: () => state.focusPane(p),
                    onClose: () => state.closePane(p),
                  ),
                )
              else
                Positioned(
                  key: ValueKey('route-$p'),
                  left: panes[p].left,
                  top: 0,
                  width: panes[p].width,
                  height: _routeBar,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (_) => state.focusPane(p),
                    child: _RouteBar(
                      state: state,
                      index: state.tabs.indexOf(shown[p]!),
                      split: state.isSplit,
                      focused: state.focus == p,
                      onClosePane: () => state.closePane(p),
                    ),
                  ),
                ),
            if (state.isSplit)
              Positioned(
                left: panes[0].right,
                top: 0,
                width: _divider,
                height: h,
                child: _Divider(
                  onDrag: (dx) => setState(
                    () =>
                        _ratio = (_ratio + dx / (w - _divider)).clamp(0.2, 0.8),
                  ),
                  onReset: () => setState(() => _ratio = 0.5),
                ),
              ),
            if (_dragging) ..._dropZones(panes),
          ],
        );
      },
    );
  }

  Widget _terminal(int i, List<Rect> panes, Rect Function(Rect) body) {
    final t = state.tabs[i];
    final pane = state.paneOf(i);
    return Positioned.fromRect(
      key: ValueKey('term-${t.id}'),
      rect: body(panes[pane ?? 0]),
      child: Offstage(
        offstage: pane == null,
        child: Listener(
          onPointerDown: (_) {
            if (pane != null) state.focusPane(pane);
          },
          child: TerminalTab(
            key: ValueKey(t.id),
            spec: t.spec,
            start: state.start,
            title: t.title,
            onExit: (code) => state.markExited(t, code),
            fontSize: state.fontSize,
            onZoom: state.zoom,
          ),
        ),
      ),
    );
  }

  /// Where a dragged tab can land: either pane of a split view, or the
  /// left / right half of a single one (the right half splits it).
  List<Widget> _dropZones(List<Rect> panes) {
    final zones = <(Rect, int, String)>[
      if (!state.isSplit) ...[
        (
          Rect.fromLTRB(panes[0].left, 0, panes[0].center.dx, panes[0].bottom),
          0,
          'Show here',
        ),
        (
          Rect.fromLTRB(panes[0].center.dx, 0, panes[0].right, panes[0].bottom),
          1,
          'Split right',
        ),
      ] else
        for (var p = 0; p < panes.length; p++) (panes[p], p, 'Show here'),
    ];
    return [
      for (final (rect, pane, label) in zones)
        Positioned.fromRect(
          key: ValueKey('drop-$pane'),
          rect: rect,
          child: DragTarget<int>(
            onAcceptWithDetails: (d) {
              final i = state.tabs.indexWhere((t) => t.id == d.data);
              if (i >= 0) state.showInPane(pane, i);
              _setDragging(false);
            },
            builder: (context, candidate, _) => candidate.isEmpty
                ? const SizedBox.expand()
                : _DropHint(label: label),
          ),
        ),
    ];
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
      text =
          'ALCF agents need alcf-ai and alcf-tokens. Install them with '
          'uv tool install alcf-ai and uv tool install alcf-tokens, then restart.';
    } else if (!state.alcfLoggedIn) {
      text =
          'You are not signed in to ALCF. ALCF agents need a login, '
          'which lasts 30 days.';
      action = FilledButton(
        onPressed: state.openLogin,
        child: const Text('Log in'),
      );
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
      child: Row(
        children: [
          Expanded(child: Text(text)),
          if (action != null) ...[const SizedBox(width: 12), action],
          if (state.alcfAvailable) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Check again',
              onPressed: state.refresh,
              icon: const Icon(
                Icons.refresh_rounded,
                size: 18,
                color: Tok.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.state, required this.onDragging});
  final AppState state;
  final ValueChanged<bool> onDragging;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Tok.rail,
        border: Border(bottom: BorderSide(color: Tok.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < state.tabs.length; i++)
                  _TabChip(state: state, index: i, onDragging: onDragging),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Tok.line)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: IconButton(
              key: const ValueKey('split-toggle'),
              tooltip: state.isSplit
                  ? 'Back to one pane'
                  : 'Split side by side (or drag a tab to the right)',
              onPressed: state.toggleSplit,
              icon: Icon(
                state.isSplit
                    ? Icons.crop_square_rounded
                    : Icons.vertical_split_outlined,
                size: 18,
                color: state.isSplit ? Tok.accent : Tok.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.state,
    required this.index,
    required this.onDragging,
  });
  final AppState state;
  final int index;
  final ValueChanged<bool> onDragging;

  Future<void> _close(BuildContext context) async {
    final t = state.tabs[index];
    if (t.running) {
      final stop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Stop ${t.title}?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          content: const Text(
            'The agent is still running. Closing the tab stops it and '
            'loses anything it has not saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(foregroundColor: Tok.muted),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Tok.danger),
              child: const Text('Stop session'),
            ),
          ],
        ),
      );
      if (stop != true) return;
    }
    final i = state.tabs.indexOf(t);
    if (i >= 0) state.close(i);
  }

  @override
  Widget build(BuildContext context) {
    final t = state.tabs[index];
    final pane = state.paneOf(index);
    // Shown in the focused pane: accent. Shown in the other pane: a quiet
    // underline, so both visible tabs read as "on screen".
    final active = pane != null && pane == state.focus;
    final visible = pane != null;
    final exited = t.exitCode != null;
    final label = exited ? '${t.title} (ended)' : t.title;
    final chip = InkWell(
      onTap: () => state.select(index),
      hoverColor: Tok.raised,
      child: Container(
        padding: const EdgeInsets.only(left: 14, right: 2),
        decoration: BoxDecoration(
          color: visible ? Tok.bg : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: active
                  ? Tok.accent
                  : (visible ? Tok.faint : Colors.transparent),
              width: 2,
            ),
            right: const BorderSide(color: Tok.line),
          ),
        ),
        child: Row(
          children: [
            if (state.isSplit && visible) ...[
              Icon(
                pane == 0 ? Icons.west_rounded : Icons.east_rounded,
                size: 12,
                color: active ? Tok.accent : Tok.faint,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: exited ? Tok.faint : (visible ? Tok.text : Tok.muted),
              ),
            ),
            IconButton(
              key: ValueKey('close-tab-$index'),
              tooltip: 'Close session',
              visualDensity: VisualDensity.compact,
              onPressed: () => _close(context),
              icon: const Icon(Icons.close_rounded, size: 15, color: Tok.faint),
            ),
          ],
        ),
      ),
    );
    return Draggable<int>(
      key: ValueKey('tab-chip-$index'),
      data: t.id,
      onDragStarted: () => onDragging(true),
      onDragEnd: (_) => onDragging(false),
      onDraggableCanceled: (_, _) => onDragging(false),
      feedback: Material(
        color: Tok.raised,
        borderRadius: BorderRadius.circular(6),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13.5, color: Tok.text),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      child: chip,
    );
  }
}

/// Says where this session's requests go. The one place the app spends
/// visual weight: running on the wrong backend is the failure this app
/// exists to prevent.
class _RouteBar extends StatelessWidget {
  const _RouteBar({
    required this.state,
    required this.index,
    this.split = false,
    this.focused = true,
    this.onClosePane,
  });
  final AppState state;
  final int index;

  /// In a split view the focused pane's bar carries an accent top line.
  final bool split;
  final bool focused;
  final VoidCallback? onClosePane;

  @override
  Widget build(BuildContext context) {
    final tab = state.tabs[index];
    final alcf = tab.profile?.isAlcf ?? true;
    final lit = !split || focused;
    return Container(
      height: 30,
      padding: EdgeInsets.only(left: 14, right: split ? 2 : 14),
      decoration: BoxDecoration(
        color: lit ? Tok.bg : Tok.rail,
        border: Border(
          top: BorderSide(
            color: split && focused ? Tok.accent : Colors.transparent,
            width: 2,
          ),
          bottom: const BorderSide(color: Tok.line),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            color: alcf && lit ? Tok.accent : Tok.muted,
          ),
          const SizedBox(width: 10),
          Text('Runs on ', style: Theme.of(context).textTheme.bodySmall),
          // The route gets the room first; the folder shrinks before it.
          Flexible(
            flex: 3,
            child: Text(
              tab.route,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: lit ? Tok.text : Tok.muted,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text(
              'in ${tab.spec.cwd}',
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (!tab.running) ...[
            const SizedBox(width: 12),
            TextButton(
              key: const ValueKey('restart-tab'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: () => state.restart(index),
              child: const Text('Restart'),
            ),
          ],
          if (split)
            IconButton(
              key: ValueKey('close-pane-${state.paneOf(index)}'),
              tooltip: 'Close this pane (the session keeps running)',
              visualDensity: VisualDensity.compact,
              onPressed: onClosePane,
              icon: const Icon(Icons.close_rounded, size: 14, color: Tok.faint),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.state});
  final AppState state;

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
            Text(
              'Start a session',
              style: t.titleMedium?.copyWith(fontSize: 22),
            ),
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
            if (state.canReopen > 0) ...[
              const SizedBox(height: 22),
              OutlinedButton(
                onPressed: state.reopenLast,
                child: Text('Reopen last sessions (${state.canReopen})'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A pane with no session yet (right after splitting with one tab).
class _EmptyPane extends StatelessWidget {
  const _EmptyPane({
    required this.focused,
    required this.onTap,
    required this.onClose,
  });
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onTap(),
      child: Container(
        decoration: BoxDecoration(
          color: Tok.bg,
          border: Border(
            top: BorderSide(
              color: focused ? Tok.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.vertical_split_outlined,
                      size: 28,
                      color: Tok.faint,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Open an agent from the left, or drag a tab here.',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(
                        color: Tok.muted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                key: const ValueKey('close-empty-pane'),
                tooltip: 'Close this pane',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Tok.faint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bar between two panes: drag to resize, double-click to even them.
class _Divider extends StatefulWidget {
  const _Divider({required this.onDrag, required this.onReset});
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: const ValueKey('pane-divider'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onDoubleTap: widget.onReset,
        child: Container(
          color: Tok.rail,
          alignment: Alignment.center,
          child: Container(
            width: _hover ? 2 : 1,
            color: _hover ? Tok.accent : Tok.line,
          ),
        ),
      ),
    );
  }
}

/// Shown over a pane while a dragged tab hovers it.
class _DropHint extends StatelessWidget {
  const _DropHint({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Tok.accent.withValues(alpha: 0.10),
        border: Border.all(color: Tok.accent, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Tok.raised,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Tok.text,
          ),
        ),
      ),
    );
  }
}
