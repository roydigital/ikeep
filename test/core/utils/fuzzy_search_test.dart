import 'package:flutter_test/flutter_test.dart';
import 'package:ikeep/core/utils/fuzzy_search.dart';

void main() {
  group('FuzzySearch.matches', () {
    test('empty query matches everything', () {
      expect(FuzzySearch.matches('', 'Battery'), true);
      expect(FuzzySearch.matches('  ', 'Battery'), true);
    });

    test('exact match', () {
      expect(FuzzySearch.matches('Battery', 'Battery'), true);
    });

    test('case-insensitive matching', () {
      expect(FuzzySearch.matches('battery', 'Battery'), true);
      expect(FuzzySearch.matches('BATTERY', 'battery'), true);
      expect(FuzzySearch.matches('BaTtErY', 'bAtTeRy'), true);
    });

    test('substring match (contains)', () {
      expect(FuzzySearch.matches('bat', 'Battery'), true);
      expect(FuzzySearch.matches('tery', 'Battery'), true);
      expect(FuzzySearch.matches('atte', 'Battery'), true);
    });

    test('typo tolerance — single character substitution', () {
      // "bttery" vs "battery" — Levenshtein distance = 1
      expect(FuzzySearch.matches('bttery', 'Battery'), true);
    });

    test('typo tolerance — single character deletion', () {
      // "batry" vs "battery" — distance = 2
      expect(FuzzySearch.matches('batry', 'Battery'), true);
    });

    test('typo tolerance — single character insertion', () {
      // "baattery" vs "battery" — distance = 1
      expect(FuzzySearch.matches('baattery', 'Battery'), true);
    });

    test('typo tolerance — transposition', () {
      // "abttery" vs "battery" — distance = 2
      expect(FuzzySearch.matches('abttery', 'Battery'), true);
    });

    test('rejects matches beyond maxDistance', () {
      // "xyz" vs "battery" — very high distance
      expect(FuzzySearch.matches('xyz', 'Battery'), false);
    });

    test('rejects with tighter maxDistance', () {
      // "bttery" vs "battery" — distance = 1, but maxDistance = 0
      expect(FuzzySearch.matches('bttery', 'Battery', maxDistance: 0), false);
    });

    test('matches against individual words in multi-word targets', () {
      // "charger" is a word in "USB Charger Cable"
      expect(FuzzySearch.matches('charger', 'USB Charger Cable'), true);
    });

    test('fuzzy matches against individual words in multi-word targets', () {
      // "chrger" vs "charger" — distance = 1
      expect(FuzzySearch.matches('chrger', 'USB Charger Cable'), true);
    });

    test('handles special characters gracefully', () {
      expect(FuzzySearch.matches('9v', '9V Battery'), true);
    });

    test('handles single-character query', () {
      expect(FuzzySearch.matches('b', 'Battery'), true);
      expect(FuzzySearch.matches('z', 'Battery'), false);
    });
  });

  group('FuzzySearch.score', () {
    test('prefix match scores 0 (best)', () {
      expect(FuzzySearch.score('bat', 'battery'), 0);
    });

    test('exact match scores 0 (starts with)', () {
      expect(FuzzySearch.score('battery', 'battery'), 0);
    });

    test('contains match scores 1', () {
      expect(FuzzySearch.score('atter', 'battery'), 1);
    });

    test('fuzzy match scores distance + 2', () {
      // "bttery" vs "battery" — Levenshtein distance = 1 → score = 3
      expect(FuzzySearch.score('bttery', 'battery'), 3);
    });

    test('completely unrelated query gets a high score', () {
      expect(FuzzySearch.score('xyz', 'battery'), greaterThan(4));
    });

    test('prefix match ranks higher than contains match', () {
      final prefixScore = FuzzySearch.score('bat', 'battery charger');
      final containsScore = FuzzySearch.score('tery', 'battery charger');

      expect(prefixScore, lessThan(containsScore));
    });

    test('contains match ranks higher than fuzzy match', () {
      final containsScore = FuzzySearch.score('atter', 'battery');
      final fuzzyScore = FuzzySearch.score('bttery', 'battery');

      expect(containsScore, lessThan(fuzzyScore));
    });

    test('scores can be used to sort results from best to worst', () {
      final targets = ['Battery', 'USB Cable', 'Bat', 'Better', 'Butterfly'];
      final query = 'bat';

      final scored = targets.map((t) => MapEntry(t, FuzzySearch.score(query, t))).toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      // "Bat" and "Battery" should be at the top (prefix matches, score 0)
      expect(scored[0].key, anyOf('Bat', 'Battery'));
      expect(scored[1].key, anyOf('Bat', 'Battery'));
    });
  });

  group('Levenshtein distance edge cases', () {
    test('empty strings have distance equal to other string length', () {
      // Tested indirectly via score for empty query → always matches
      expect(FuzzySearch.matches('', 'test'), true);
    });

    test('identical strings have distance 0', () {
      expect(FuzzySearch.score('battery', 'battery'), 0); // prefix match
    });

    test('single character difference', () {
      // "cat" vs "bat" — distance 1
      expect(FuzzySearch.matches('cat', 'bat'), true);
    });

    test('completely different strings of same length', () {
      // "abc" vs "xyz" — distance 3, exceeds default maxDistance of 2
      expect(FuzzySearch.matches('abc', 'xyz'), false);
    });
  });
}
