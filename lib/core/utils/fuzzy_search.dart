/// Simple fuzzy search utilities for item name matching.
/// Uses Levenshtein distance for "close enough" matching.
class FuzzySearch {
  FuzzySearch._();

  /// Returns true if [query] fuzzy-matches [target].
  /// First tries contains (case-insensitive), then Levenshtein on each word.
  static bool matches(String query, String target, {int maxDistance = 2}) {
    final q = query.toLowerCase().trim();
    final t = target.toLowerCase();

    if (q.isEmpty) return true;
    if (t.contains(q)) return true;

    // Check each word in the target against the query
    final words = t.split(RegExp(r'\s+'));
    for (final word in words) {
      if (_levenshtein(q, word) <= maxDistance) return true;
    }
    return false;
  }

  /// Scores a match (lower = better). Used for sorting results.
  static int score(String query, String target) {
    final q = query.toLowerCase().trim();
    final t = target.toLowerCase();
    if (t.startsWith(q)) return 0;
    if (t.contains(q)) return 1;
    final words = t.split(RegExp(r'\s+'));
    int best = 999;
    for (final word in words) {
      final d = _levenshtein(q, word);
      if (d < best) best = d;
    }
    return best + 2;
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    final rows = List<List<int>>.generate(
      s.length + 1,
      (i) => List<int>.generate(t.length + 1, (j) => j == 0 ? i : 0),
    );
    for (int j = 1; j <= t.length; j++) {
      rows[0][j] = j;
    }
    for (int i = 1; i <= s.length; i++) {
      for (int j = 1; j <= t.length; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        rows[i][j] = [
          rows[i - 1][j] + 1,
          rows[i][j - 1] + 1,
          rows[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return rows[s.length][t.length];
  }
}
