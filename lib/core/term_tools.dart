/// Small text helpers for the terminal tab: link detection, search, zoom.
library;

const kDefaultFontSize = 13.5;
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
    ? kDefaultFontSize
    : (size + step).clamp(kMinFontSize, kMaxFontSize).toDouble();
