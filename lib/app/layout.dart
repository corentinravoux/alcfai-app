/// The split layout of the terminal area: a binary tree, as in VS Code.
/// Leaves are panes (each shows one tab, or nothing); inner nodes split
/// their area in two, side by side or one above the other.
library;

import 'dart:ui' show Rect;

enum Side { left, right, top, bottom }

sealed class LayoutNode {}

class PaneNode extends LayoutNode {
  PaneNode(this.id, [this.tab]);

  final int id;

  /// Id of the tab shown, or null for an empty pane.
  int? tab;
}

class SplitNode extends LayoutNode {
  SplitNode({
    required this.sideBySide,
    required this.first,
    required this.second,
    this.ratio = 0.5,
  });

  /// True: [first] left of [second]. False: [first] above [second].
  final bool sideBySide;
  LayoutNode first;
  LayoutNode second;

  /// Share of the width (or height) given to [first].
  double ratio;
}

/// Panes from left to right, top to bottom.
List<PaneNode> panesOf(LayoutNode n) => switch (n) {
  PaneNode() => [n],
  SplitNode() => [...panesOf(n.first), ...panesOf(n.second)],
};

/// The split holding [child] directly, or null for the root.
SplitNode? parentOf(LayoutNode root, LayoutNode child) {
  if (root is! SplitNode) return null;
  if (identical(root.first, child) || identical(root.second, child)) {
    return root;
  }
  return parentOf(root.first, child) ?? parentOf(root.second, child);
}

/// [root] with [target] replaced by [by] (the tree is changed in place;
/// the returned node is the new root).
LayoutNode replaceNode(LayoutNode root, LayoutNode target, LayoutNode by) {
  if (identical(root, target)) return by;
  final parent = parentOf(root, target);
  if (parent == null) return root;
  if (identical(parent.first, target)) {
    parent.first = by;
  } else {
    parent.second = by;
  }
  return root;
}

/// A divider between the two halves of [split], drawn in [rect]; dragging
/// it by one pixel changes the ratio by 1 / [extent].
class DividerSpec {
  const DividerSpec(this.split, this.rect, this.extent);
  final SplitNode split;
  final Rect rect;
  final double extent;
}

class LayoutGeometry {
  final panes = <int, Rect>{};
  final dividers = <DividerSpec>[];
}

/// Rectangles of every pane and divider when [root] fills [area].
LayoutGeometry measure(LayoutNode root, Rect area, {double divider = 7}) {
  final g = LayoutGeometry();
  void walk(LayoutNode n, Rect r) {
    switch (n) {
      case PaneNode():
        g.panes[n.id] = r;
      case SplitNode():
        if (n.sideBySide) {
          final usable = r.width - divider;
          final w = usable * n.ratio;
          walk(n.first, Rect.fromLTWH(r.left, r.top, w, r.height));
          g.dividers.add(
            DividerSpec(
              n,
              Rect.fromLTWH(r.left + w, r.top, divider, r.height),
              usable,
            ),
          );
          walk(
            n.second,
            Rect.fromLTRB(r.left + w + divider, r.top, r.right, r.bottom),
          );
        } else {
          final usable = r.height - divider;
          final h = usable * n.ratio;
          walk(n.first, Rect.fromLTWH(r.left, r.top, r.width, h));
          g.dividers.add(
            DividerSpec(
              n,
              Rect.fromLTWH(r.left, r.top + h, r.width, divider),
              usable,
            ),
          );
          walk(
            n.second,
            Rect.fromLTRB(r.left, r.top + h + divider, r.right, r.bottom),
          );
        }
    }
  }

  walk(root, area);
  return g;
}

/// Where a dragged tab lands in a pane: the middle shows it there, a band
/// along an edge splits the pane on that side.
enum DropZone { center, left, right, top, bottom }

/// The zone of [pane] under [x], [y] (pane-relative fractions 0..1).
/// Edge bands are a quarter of the pane; corners go to the nearer edge.
DropZone zoneAt(double x, double y) {
  const band = 0.25;
  final d = {
    DropZone.left: x,
    DropZone.right: 1 - x,
    DropZone.top: y,
    DropZone.bottom: 1 - y,
  };
  final nearest = d.entries.reduce((a, b) => a.value <= b.value ? a : b);
  return nearest.value < band ? nearest.key : DropZone.center;
}

/// The part of [pane] a drop in [zone] would fill: the preview drawn while
/// dragging.
Rect previewRect(Rect pane, DropZone zone) => switch (zone) {
  DropZone.center => pane,
  DropZone.left => Rect.fromLTWH(
    pane.left,
    pane.top,
    pane.width / 2,
    pane.height,
  ),
  DropZone.right => Rect.fromLTRB(
    pane.center.dx,
    pane.top,
    pane.right,
    pane.bottom,
  ),
  DropZone.top => Rect.fromLTWH(
    pane.left,
    pane.top,
    pane.width,
    pane.height / 2,
  ),
  DropZone.bottom => Rect.fromLTRB(
    pane.left,
    pane.center.dy,
    pane.right,
    pane.bottom,
  ),
};

Side? sideOf(DropZone z) => switch (z) {
  DropZone.center => null,
  DropZone.left => Side.left,
  DropZone.right => Side.right,
  DropZone.top => Side.top,
  DropZone.bottom => Side.bottom,
};
