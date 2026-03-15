import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/fuzzy_search.dart';
import '../domain/models/item.dart';
import 'repository_providers.dart';

// ── Search state ──────────────────────────────────────────────────────────────

final itemSearchQueryProvider = StateProvider<String>((ref) => '');

// ── Data providers ────────────────────────────────────────────────────────────

final allItemsProvider = FutureProvider<List<Item>>((ref) async {
  return ref.watch(itemRepositoryProvider).getAllItems();
});

final archivedItemsProvider = FutureProvider<List<Item>>((ref) async {
  return ref.watch(itemRepositoryProvider).getArchivedItems();
});

final itemsByLocationProvider =
    FutureProvider.family<List<Item>, String>((ref, locationUuid) async {
  return ref.watch(itemRepositoryProvider).getItemsByLocation(locationUuid);
});

final singleItemProvider =
    FutureProvider.family<Item?, String>((ref, uuid) async {
  return ref.watch(itemRepositoryProvider).getItem(uuid);
});

/// Derived search results — watches [itemSearchQueryProvider] and re-runs
/// whenever the query changes.
final searchResultsProvider = FutureProvider<List<Item>>((ref) async {
  final query = ref.watch(itemSearchQueryProvider);
  if (query.trim().isEmpty) {
    return ref.watch(itemRepositoryProvider).getAllItems();
  }

  // SQL pre-filter, then in-memory fuzzy sort
  final sqlResults = await ref.watch(itemRepositoryProvider).searchItems(query);
  sqlResults.sort((a, b) {
    final scoreA = FuzzySearch.score(query, a.name);
    final scoreB = FuzzySearch.score(query, b.name);
    return scoreA.compareTo(scoreB);
  });
  return sqlResults;
});

// ── Notifier for mutations ────────────────────────────────────────────────────

class ItemsNotifier extends StateNotifier<bool> {
  ItemsNotifier(this._ref) : super(false);

  final Ref _ref;

  Future<String?> saveItem(Item item) async {
    final failure =
        await _ref.read(itemRepositoryProvider).saveItem(item);
    if (failure != null) return failure.message;
    _ref.invalidate(allItemsProvider);
    return null;
  }

  Future<String?> updateItem(Item item) async {
    final failure =
        await _ref.read(itemRepositoryProvider).updateItem(item);
    if (failure != null) return failure.message;
    _ref.invalidate(allItemsProvider);
    _ref.invalidate(singleItemProvider(item.uuid));
    return null;
  }

  Future<String?> archiveItem(String uuid) async {
    final failure =
        await _ref.read(itemRepositoryProvider).archiveItem(uuid);
    if (failure != null) return failure.message;
    _ref.invalidate(allItemsProvider);
    _ref.invalidate(singleItemProvider(uuid));
    return null;
  }

  Future<String?> deleteItem(String uuid) async {
    final failure =
        await _ref.read(itemRepositoryProvider).deleteItem(uuid);
    if (failure != null) return failure.message;
    _ref.invalidate(allItemsProvider);
    return null;
  }
}

final itemsNotifierProvider =
    StateNotifierProvider<ItemsNotifier, bool>((ref) => ItemsNotifier(ref));
