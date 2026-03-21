import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/fuzzy_search.dart';
import '../domain/models/item.dart';
import '../domain/models/sync_status.dart';
import 'location_providers.dart';
import 'repository_providers.dart';
import 'service_providers.dart';
import 'settings_provider.dart';
import 'sync_providers.dart';

// ── Search state ──────────────────────────────────────────────────────────────

final itemSearchQueryProvider = StateProvider<String>((ref) => '');

// ── Data providers ────────────────────────────────────────────────────────────

final allItemsProvider = FutureProvider<List<Item>>((ref) async {
  return ref.watch(itemRepositoryProvider).getAllItems();
});

final archivedItemsProvider = FutureProvider<List<Item>>((ref) async {
  return ref.watch(itemRepositoryProvider).getArchivedItems();
});

final lentItemsProvider = FutureProvider<List<Item>>((ref) async {
  final items = await ref.watch(itemRepositoryProvider).getAllItems();
  final lent = items.where((item) => item.isLent && !item.isArchived).toList();
  lent.sort((a, b) {
    final aDate = a.expectedReturnDate ?? a.lentOn ?? a.savedAt;
    final bDate = b.expectedReturnDate ?? b.lentOn ?? b.savedAt;
    return aDate.compareTo(bDate);
  });
  return lent;
});

final lendableItemsProvider = FutureProvider<List<Item>>((ref) async {
  final items = await ref.watch(itemRepositoryProvider).getAllItems();
  final lendable = items
      .where((item) => item.isAvailableForLending && !item.isArchived)
      .toList();
  lendable.sort((a, b) {
    if (a.isLent != b.isLent) return a.isLent ? 1 : -1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return lendable;
});

final forgottenItemsProvider = FutureProvider<List<Item>>((ref) async {
  final now = DateTime.now();
  final eightMonthsAgo = DateTime(now.year, now.month - 8, now.day);

  final items = await ref.watch(itemRepositoryProvider).getAllItems();
  final candidates = items
      .where(
        (item) =>
            !item.isArchived &&
            item.imagePaths.isNotEmpty &&
            item.savedAt.isBefore(eightMonthsAgo),
      )
      .toList();

  if (candidates.length <= 5) {
    candidates.sort((a, b) => a.savedAt.compareTo(b.savedAt));
    return candidates;
  }

  // Stable weekly shuffle so Sunday cards feel fresh but not random on refresh.
  final random = Random(now.year * 100 + _weekOfYear(now));
  final pool = [...candidates];
  final picked = <Item>[];
  while (picked.length < 5 && pool.isNotEmpty) {
    picked.add(pool.removeAt(random.nextInt(pool.length)));
  }
  picked.sort((a, b) => a.savedAt.compareTo(b.savedAt));
  return picked;
});

int _weekOfYear(DateTime date) {
  final firstDay = DateTime(date.year, 1, 1);
  final dayOfYear = date.difference(firstDay).inDays + 1;
  return ((dayOfYear - date.weekday + 10) / 7).floor();
}

final itemsByLocationProvider =
    FutureProvider.autoDispose.family<List<Item>, String>((ref, locationUuid) async {
  return ref.watch(itemRepositoryProvider).getItemsByLocation(locationUuid);
});

final singleItemProvider =
    FutureProvider.autoDispose.family<Item?, String>((ref, uuid) async {
  return ref.watch(itemRepositoryProvider).getItem(uuid);
});

/// Derived search results — watches [itemSearchQueryProvider] and re-runs
/// whenever the query changes.
final searchResultsProvider = FutureProvider.autoDispose<List<Item>>((ref) async {
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
    final preparedItem = await _prepareItem(item);
    final failure =
        await _ref.read(itemRepositoryProvider).saveItem(preparedItem);
    if (failure != null) return failure.message;

    final syncError = await _syncItemToCloud(preparedItem);
    await _syncNotificationsForItem(preparedItem);

    _invalidateItemLists();
    return syncError;
  }

  Future<String?> updateItem(Item item) async {
    final preparedItem = await _prepareItem(item);
    final failure =
        await _ref.read(itemRepositoryProvider).updateItem(preparedItem);
    if (failure != null) return failure.message;

    final syncError = await _syncItemToCloud(
      preparedItem.copyWith(updatedAt: DateTime.now()),
    );
    await _syncNotificationsForItem(preparedItem);

    _invalidateItemLists();
    _ref.invalidate(singleItemProvider(preparedItem.uuid));
    return syncError;
  }

  Future<String?> saveItemWithMover(
    Item item, {
    String? movedByMemberUuid,
    String? movedByName,
  }) async {
    final preparedItem = await _prepareItem(item);
    final failure = await _ref.read(itemRepositoryProvider).saveItem(
          preparedItem,
          movedByMemberUuid: movedByMemberUuid,
          movedByName: movedByName,
        );
    if (failure != null) return failure.message;

    final syncError = await _syncItemToCloud(preparedItem);
    await _syncNotificationsForItem(preparedItem);

    _invalidateItemLists();
    return syncError;
  }

  Future<String?> updateItemWithMover(
    Item item, {
    String? movedByMemberUuid,
    String? movedByName,
  }) async {
    final preparedItem = await _prepareItem(item);
    final failure = await _ref.read(itemRepositoryProvider).updateItem(
          preparedItem,
          movedByMemberUuid: movedByMemberUuid,
          movedByName: movedByName,
        );
    if (failure != null) return failure.message;

    final syncError = await _syncItemToCloud(
      preparedItem.copyWith(updatedAt: DateTime.now()),
    );
    await _syncNotificationsForItem(preparedItem);

    _invalidateItemLists();
    _ref.invalidate(singleItemProvider(preparedItem.uuid));
    return syncError;
  }

  Future<String?> archiveItem(String uuid) async {
    final failure = await _ref.read(itemRepositoryProvider).archiveItem(uuid);
    if (failure != null) return failure.message;

    final archivedItem = await _ref.read(itemRepositoryProvider).getItem(uuid);
    if (archivedItem != null) {
      await _syncItemToCloud(archivedItem);
    }

    await _ref.read(notificationServiceProvider).cancelExpiryReminder(uuid);
    await _ref.read(notificationServiceProvider).cancelLentReminder(uuid);

    _ref.invalidate(allItemsProvider);
    _ref.invalidate(lentItemsProvider);
    _ref.invalidate(lendableItemsProvider);
    _ref.invalidate(forgottenItemsProvider);
    _ref.invalidate(singleItemProvider(uuid));
    return null;
  }

  Future<String?> deleteItem(String uuid) async {
    final failure = await _ref.read(itemRepositoryProvider).deleteItem(uuid);
    if (failure != null) return failure.message;

    await _syncDeleteItem(uuid);

    await _ref.read(notificationServiceProvider).cancelExpiryReminder(uuid);
    await _ref.read(notificationServiceProvider).cancelLentReminder(uuid);

    _ref.invalidate(allItemsProvider);
    _ref.invalidate(lentItemsProvider);
    _ref.invalidate(lendableItemsProvider);
    _ref.invalidate(forgottenItemsProvider);
    return null;
  }

  Future<String?> _syncItemToCloud(Item item) async {
    if (!item.isBackedUp) {
      final hadRemoteBackup = (item.cloudId?.trim().isNotEmpty ?? false) ||
          item.lastSyncedAt != null;
      if (hadRemoteBackup) {
        await _syncDeleteItem(item.uuid);
        await _ref.read(itemRepositoryProvider).updateItem(
              item.copyWith(
                clearCloudId: true,
                clearLastSyncedAt: true,
              ),
            );
      }
      return null;
    }

    final result = await _ref.read(syncServiceProvider).syncItem(item);
    _ref.read(syncStatusProvider.notifier).state = result;
    _ref.invalidate(lastSyncedAtProvider);

    if (result.status != SyncStatus.error) {
      return null;
    }

    if (_isCloudQuotaExceeded(result.errorMessage)) {
      await _ref.read(itemRepositoryProvider).updateItem(
            item.copyWith(
              isBackedUp: false,
              clearCloudId: true,
              clearLastSyncedAt: true,
            ),
          );
      _invalidateItemLists();
      _ref.invalidate(singleItemProvider(item.uuid));
    }

    return result.errorMessage ?? 'Sync failed';
  }

  Future<void> _syncDeleteItem(String uuid) async {
    final result = await _ref.read(syncServiceProvider).deleteRemoteItem(uuid);
    if (result.status != SyncStatus.error) {
      _ref.read(syncStatusProvider.notifier).state = result;
      _ref.invalidate(lastSyncedAtProvider);
    }
  }

  Future<void> _syncNotificationsForItem(Item item) async {
    final notificationService = _ref.read(notificationServiceProvider);
    final settings = _ref.read(settingsProvider);
    final shouldScheduleNotifications = settings.expiryRemindersEnabled ||
        (settings.lentRemindersEnabled && item.isLent);

    if (shouldScheduleNotifications) {
      await notificationService.requestPermissionsIfNeeded();
    }

    if (settings.expiryRemindersEnabled) {
      await notificationService.scheduleExpiryReminder(item);
    } else {
      await notificationService.cancelExpiryReminder(item.uuid);
    }

    if (settings.lentRemindersEnabled && item.isLent) {
      await notificationService.scheduleLentReminder(item);
    } else {
      await notificationService.cancelLentReminder(item.uuid);
    }
  }

  Future<Item> _prepareItem(Item item) async {
    final seasonCategory =
        await _ref.read(mlLabelServiceProvider).classifySeasonCategory(
              itemName: item.name,
              tags: item.tags,
              imagePaths: item.imagePaths,
            );
    return item.copyWith(seasonCategory: seasonCategory);
  }

  void _invalidateItemLists() {
    _ref.invalidate(allItemsProvider);
    _ref.invalidate(lentItemsProvider);
    _ref.invalidate(lendableItemsProvider);
    _ref.invalidate(forgottenItemsProvider);
    _ref.invalidate(allLocationsProvider);
    _ref.invalidate(rootLocationsProvider);
    _ref.invalidate(backedUpItemsCountProvider);
  }

  bool _isCloudQuotaExceeded(String? message) {
    return (message ?? '').contains('Cloud quota exceeded');
  }
}

final itemsNotifierProvider =
    StateNotifierProvider<ItemsNotifier, bool>((ref) => ItemsNotifier(ref));
