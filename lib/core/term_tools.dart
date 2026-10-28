/// Small text helpers for the terminal tab: cell text, link detection,
/// search, zoom.
library;

import 'package:xterm/core.dart';

const kTermFontSize = 13.5;
const kMinFontSize = 9.0;
const kMaxFontSize = 24.0;

final _url = RegExp(r'''https?://[^\s<>"'()\[\]{}]+''');

/// The URL covering column [col] of [line], without trailing punctuation.
String? urlAt(String line, int col) {
  for (final m in _url.allMatches(line)) {
    final url = m.group(0)!.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
    if (col >= m.start && col < m.start + url.length) return url;
  }
  return null;
}

class TextHit {
  const TextHit(this.line, this.start, this.end);
  final int line;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is TextHit &&
      other.line == line &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(line, start, end);

  @override
  String toString() => 'TextHit($line, $start, $end)';
}

/// Every case-insensitive occurrence of [query], in reading order.
List<TextHit> findAll(List<String> lines, String query) {
  if (query.isEmpty) return const [];
  final q = query.toLowerCase();
  final hits = <TextHit>[];
  for (var y = 0; y < lines.length; y++) {
    final l = lines[y].toLowerCase();
    var i = l.indexOf(q);
    while (i >= 0) {
      hits.add(TextHit(y, i, i + q.length));
      i = l.indexOf(q, i + q.length);
    }
  }
  return hits;
}

/// Next font size: step +1 / -1 zooms, 0 resets.
double zoomed(double size, int step) => step == 0
    ? kTermFontSize
    : (size + step).clamp(kMinFontSize, kMaxFontSize).toDouble();

/// Text of cells [from, to) of [line].
///
/// Unlike xterm's `BufferLine.getText`, a cell that was never written reads
/// as a space: full-screen UIs such as codex (ratatui) move the cursor over
/// blank cells instead of printing spaces, and getText drops those cells,
/// gluing words together. The empty cell after a wide character is still
/// skipped. Trailing blanks are trimmed when [trimEnd].
String lineText(BufferLine line, {int from = 0, int? to, bool trimEnd = true}) {
  final end = to == null || to > line.length ? line.length : to;
  final b = StringBuffer();
  for (var i = from < 0 ? 0 : from; i < end; i++) {
    final cp = line.getCodePoint(i);
    if (cp != 0) {
      if (i + line.getWidth(i) <= end) b.writeCharCode(cp);
    } else if (i == 0 || line.getWidth(i - 1) != 2) {
      b.write(' ');
    }
  }
  final text = b.toString();
  return trimEnd ? text.trimRight() : text;
}

/// The text of [range], as `Buffer.getText` builds it but with [lineText]:
/// a newline between lines unless the next one is a wrapped continuation.
String selectionText(Buffer buffer, BufferRange range) {
  final r = range.normalized;
  final b = StringBuffer();
  final lines = buffer.lines;
  for (final seg in r.toSegments()) {
    if (seg.line < 0 || seg.line >= buffer.height) continue;
    final line = lines[seg.line];
    if (seg.line != r.begin.y && seg.line != 0 && !line.isWrapped) {
      b.write('\n');
    }
    // Trim when nothing but blanks follows the segment on its line.
    final reachesEnd =
        seg.end == null || lineText(line, from: seg.end!).isEmpty;
    final nextWrapped =
        seg.line + 1 < buffer.height && lines[seg.line + 1].isWrapped;
    b.write(
      lineText(
        line,
        from: seg.start ?? 0,
        to: seg.end,
        trimEnd: reachesEnd && !nextWrapped,
      ),
    );
  }
  return b.toString();
}
