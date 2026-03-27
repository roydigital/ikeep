import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/fuzzy_search.dart';
import '../domain/models/item.dart';
import 'database_provider.dart';
import '../domain/models/sync_status.dart';
import 'location_providers.dart';
import 'repository_providers.dart';
import '../services/invoice_service.dart';
import 'service_providers.dart';
import 'settings_provider.dart';
import 'sync_providers.dart';

// ── Search state ──────────────────────────────────────────────────────────────

final itemSearchQueryProvider = StateProvider<String>((ref) => '');

const int dashboardExpiringSoonWindowDays = 14;
const int dashboardWarrantyEndingSoonWindowDays = 30;

DateTime dashboardDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool isItemExpiringSoon(
  Item item, {
  DateTime? referenceDate,
  int withinDays = dashboardExpiringSoonWindowDays,
}) {
  final expiryDate = item.expiryDate;
  if (item.isArchived || expiryDate == null) return false;

  final today = dashboardDateOnly(referenceDate ?? DateTime.now());
  final expiryDay = dashboardDateOnly(expiryDate);
  final daysUntilExpiry = expiryDay.difference(today).inDays;
  return daysUntilExpiry >= 0 && daysUntilExpiry <= withinDays;
}

bool isItemWarrantyEndingSoon(
  Item item, {
  DateTime? referenceDate,
  int withinDays = dashboardWarrantyEndingSoonWindowDays,
}) {
  final warrantyEndDate = item.warrantyEndDate;
  if (item.isArchived || warrantyEndDate == null) return false;

  final today = dashboardDateOnly(referenceDate ?? DateTime.now());
  final warrantyDay = dashboardDateOnly(warrantyEndDate);
  final daysUntilEnd = warrantyDay.difference(today).inDays;
  return daysUntilEnd >= 0 && daysUntilEnd <= withinDays;
}

DateTime lentDashboardSortDate(Item item) {
  final sourceDate = item.expectedReturnDate ?? item.lentOn ?? item.savedAt;
  return dashboardDateOnly(sourceDate);
}

int compareLentItemsForDashboard(Item a, Item b) {
  final aHasReturnDate = a.expectedReturnDate != null;
  final bHasReturnDate = b.expectedReturnDate != null;
  if (aHasReturnDate != bHasReturnDate) {
    return aHasReturnDate ? -1 : 1;
  }

  final dateCompare = lentDashboardSortDate(a).compareTo(
    lentDashboardSortDate(b),
  );
  if (dateCompare != 0) return dateCompare;

  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

int compareExpiringItemsForDashboard(Item a, Item b) {
  final aExpiryDate = a.expiryDate;
  final bExpiryDate = b.expiryDate;
  if (aExpiryDate == null && bExpiryDate == null) {
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
  if (aExpiryDate == null) return 1;
  if (bExpiryDate == null) return -1;

  final dateCompare = dashboardDateOnly(aExpiryDate).compareTo(
    dashboardDateOnly(bExpiryDate),
  );
  if (dateCompare != 0) return dateCompare;

  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

int compareWarrantyItemsForDashboard(Item a, Item b) {
  final aWarrantyDate = a.warrantyEndDate;
  final bWarrantyDate = b.warrantyEndDate;
  if (aWarrantyDate == null && bWarrantyDate == null) {
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
  if (aWarrantyDate == null) return 1;
  if (bWarrantyDate == null) return -1;

  final dateCompare = dashboardDateOnly(aWarrantyDate).compareTo(
    dashboardDateOnly(bWarrantyDate),
  );
  if (dateCompare != 0) return dateCompare;

  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

// ── Data providers ────────────────────────────────────────────────────────────

final allItemsProvider = FutureProvider<List<Item>>((ref) async {
  return ref.watch(itemRepositoryProvider).getAllItems();
});

final backedUpItemsProvider = FutureProvider<List<Item>>((ref) async {
  final items = await ref.watch(allItemsProvider.future);
  final backedUpItems = items.where((item) => item.isBackedUp).toList()
    ..sort((a, b) {
      final aDate = a.updatedAt ?? a.savedAt;
      final bDate = b.updatedAt ?? b.savedAt;
      return bDate.compareTo(aDate);
    });
  return backedUpItems;
});

final itemTagsProvider = FutureProvider<List<String>>((ref) async {
  return ref.watch(itemDaoProvider).getAllTags();
});

final archivedItemsProvider = FutureProvider<List<Item>>((ref) async {
  return ref.watch(itemRepositoryProvider).getArchivedItems();
});

final lentItemsProvider = FutureProvider<List<Item>>((ref) async {
  final items = await ref.watch(allItemsProvider.future);
  final lent = items.where((item) => item.isLent && !item.isArchived).toList();
  lent.sort(compareLentItemsForDashboard);
  return lent;
});

final expiringSoonItemsProvider = FutureProvider<List<Item>>((ref) async {
  final items = await ref.watch(allItemsProvider.future);
  final expiringSoon = items.where((item) => isItemExpiringSoon(item)).toList()
    ..sort(compareExpiringItemsForDashboard);
  return expiringSoon;
});

final warrantyEndingSoonItemsProvider = FutureProvider<List<Item>>((ref) async {
  final items = await ref.watch(allItemsProvider.future);
  final warrantyEndingSoon = items
      .where((item) => isItemWarrantyEndingSoon(item))
      .toList()
    ..sort(compareWarrantyItemsForDashboard);
  return warrantyEndingSoon;
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

final itemsByLocationProvider = FutureProvider.autoDispose
    .family<List<Item>, String>((ref, locationUuid) async {
  return ref.watch(itemRepositoryProvider).getItemsByLocation(locationUuid);
});

final singleItemProvider =
    FutureProvider.autoDispose.family<Item?, String>((ref, uuid) async {
  return ref.watch(itemRepositoryProvider).getItem(uuid);
});

/// Derived search results — watches [itemSearchQueryProvider] and re-runs
/// whenever the query changes.
final searchResultsProvider =
    FutureProvider.autoDispose<List<Item>>((ref) async {
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
  static const _deleteReasonDeleted = 'deleted';
  static const _deleteReasonBackupDisabled = 'backup_disabled';

  ItemsNotifier(this._ref) : super(false);

  final Ref _ref;

  Future<String?> saveItem(Item item) async {
    final preparedItem = await _prepareItem(item);
    final failure =
        await _ref.read(itemRepositoryProvider).saveItem(preparedItem);
    if (failure != null) return failure.message;

    final storedItem =
        await _ref.read(itemRepositoryProvider).getItem(preparedItem.uuid) ??
            preparedItem;

    await _syncNotificationsForItem(storedItem);
    final syncError = await _preflightCloudSync(item: storedItem);

    _invalidateItemLists();
    if (syncError == null) {
      _scheduleCloudSync(item: storedItem);
    }
    return syncError;
  }

  Future<String?> updateItem(Item item) async {
    final existingItem =
        await _ref.read(itemRepositoryProvider).getItem(item.uuid);
    final preparedItem = await _prepareItemForUpdate(
      item,
      existingItem: existingItem,
    );
    final failure =
        await _ref.read(itemRepositoryProvider).updateItem(preparedItem);
    if (failure != null) return failure.message;

    final storedItem =
        await _ref.read(itemRepositoryProvider).getItem(preparedItem.uuid) ??
            preparedItem;

    await _syncNotificationsForItem(storedItem);
    final syncError = await _preflightCloudSync(
      item: storedItem,
      hadRemoteBackup: _hasRemoteBackup(existingItem),
    );

    _invalidateItemLists();
    _ref.invalidate(singleItemProvider(preparedItem.uuid));
    if (syncError == null) {
      _scheduleCloudSync(
        item: storedItem,
        hadRemoteBackup: _hasRemoteBackup(existingItem),
      );
    }
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

    final storedItem =
        await _ref.read(itemRepositoryProvider).getItem(preparedItem.uuid) ??
            preparedItem;

    await _syncNotificationsForItem(storedItem);
    final syncError = await _preflightCloudSync(item: storedItem);

    _invalidateItemLists();
    if (syncError == null) {
      _scheduleCloudSync(item: storedItem);
    }
    return syncError;
  }

  Future<String?> updateItemWithMover(
    Item item, {
    String? movedByMemberUuid,
    String? movedByName,
  }) async {
    final existingItem =
        await _ref.read(itemRepositoryProvider).getItem(item.uuid);
    final preparedItem = await _prepareItemForUpdate(
      item,
      existingItem: existingItem,
    );
    final failure = await _ref.read(itemRepositoryProvider).updateItem(
          preparedItem,
          movedByMemberUuid: movedByMemberUuid,
          movedByName: movedByName,
        );
    if (failure != null) return failure.message;

    final storedItem =
        await _ref.read(itemRepositoryProvider).getItem(preparedItem.uuid) ??
            preparedItem;

    await _syncNotificationsForItem(storedItem);
    final syncError = await _preflightCloudSync(
      item: storedItem,
      hadRemoteBackup: _hasRemoteBackup(existingItem),
    );

    _invalidateItemLists();
    _ref.invalidate(singleItemProvider(preparedItem.uuid));
    if (syncError == null) {
      _scheduleCloudSync(
        item: storedItem,
        hadRemoteBackup: _hasRemoteBackup(existingItem),
      );
    }
    return syncError;
  }

  Future<ArchiveItemResult> archiveItem(String uuid) async {
    final failure = await _ref.read(itemRepositoryProvider).archiveItem(uuid);
    if (failure != null) {
      return ArchiveItemResult.failure(failure.message);
    }

    final archivedItem = await _ref.read(itemRepositoryProvider).getItem(uuid);
    String? cloudWarning;
    if (archivedItem != null) {
      final previousStatus = _ref.read(syncStatusProvider);
      cloudWarning = await _syncItemToCloud(
        archivedItem,
        fallbackStatus: previousStatus,
        publishErrorsToStatus: false,
      );
    }

    await _ref.read(notificationServiceProvider).cancelExpiryReminder(uuid);
    await _ref.read(notificationServiceProvider).cancelLentReminder(uuid);

    _ref.invalidate(allItemsProvider);
    _ref.invalidate(lentItemsProvider);
    _ref.invalidate(expiringSoonItemsProvider);
    _ref.invalidate(warrantyEndingSoonItemsProvider);
    _ref.invalidate(lendableItemsProvider);
    _ref.invalidate(forgottenItemsProvider);
    _ref.invalidate(itemTagsProvider);
    _ref.invalidate(singleItemProvider(uuid));
    return ArchiveItemResult.success(cloudWarning: cloudWarning);
  }

  Future<String?> deleteItem(String uuid) async {
    final existingItem = await _ref.read(itemRepositoryProvider).getItem(uuid);
    final failure = await _ref.read(itemRepositoryProvider).deleteItem(uuid);
    if (failure != null) return failure.message;

    if (existingItem != null && _hasRemoteBackup(existingItem)) {
      await _syncDeleteItem(
        uuid,
        reason: _deleteReasonDeleted,
      );
    }

    final invoicePath = existingItem?.invoicePath?.trim();
    if (invoicePath != null &&
        InvoiceService.isSafeLocalInvoicePath(invoicePath)) {
      await _ref.read(invoiceServiceProvider).deleteInvoice(invoicePath);
    }

    await _ref.read(notificationServiceProvider).cancelExpiryReminder(uuid);
    await _ref.read(notificationServiceProvider).cancelLentReminder(uuid);

    _ref.invalidate(allItemsProvider);
    _ref.invalidate(lentItemsProvider);
    _ref.invalidate(expiringSoonItemsProvider);
    _ref.invalidate(warrantyEndingSoonItemsProvider);
    _ref.invalidate(lendableItemsProvider);
    _ref.invalidate(forgottenItemsProvider);
    _ref.invalidate(itemTagsProvider);
    return null;
  }

  /// Enables cloud backup for [item]: persists [isBackedUp = true] to the
  /// local database and immediately runs the Firebase sync, awaiting the
  /// full result (including image uploads).
  ///
  /// Returns null on full success, an error/warning string on failure.
  /// Unlike [updateItem], the sync is NOT deferred — the caller blocks until
  /// images and metadata are confirmed uploaded.
  Future<String?> backupItem(Item item) async {
    final syncItem = item.copyWith(isBackedUp: true, updatedAt: DateTime.now());
    final failure =
        await _ref.read(itemRepositoryProvider).updateItem(syncItem);
    if (failure != null) return failure.message;

    final storedItem =
        await _ref.read(itemRepositoryProvider).getItem(item.uuid) ?? syncItem;

    final previousStatus = _ref.read(syncStatusProvider);
    _ref.read(syncStatusProvider.notifier).state = const SyncResult.syncing();

    final syncError =
        await _syncItemToCloud(storedItem, fallbackStatus: previousStatus);

    _invalidateItemLists();
    _ref.invalidate(singleItemProvider(item.uuid));

    return syncError;
  }

  Future<String?> _syncItemToCloud(
    Item item, {
    SyncResult? fallbackStatus,
    bool publishErrorsToStatus = true,
  }) async {
    if (!item.isBackedUp) {
      final hadRemoteBackup = (item.cloudId?.trim().isNotEmpty ?? false) ||
          item.lastSyncedAt != null;
      if (hadRemoteBackup) {
        final deleteResult = await _syncDeleteItem(
          item.uuid,
          reason: _deleteReasonBackupDisabled,
          fallbackStatus: fallbackStatus,
          publishErrorsToStatus: publishErrorsToStatus,
        );
        if (deleteResult.status == SyncStatus.error) {
          return deleteResult.errorMessage ?? 'Sync failed';
        }
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
    publishSyncResult(
      _ref,
      result,
      publishErrors: publishErrorsToStatus,
      fallbackStatus: fallbackStatus,
    );

    // Photos failed to upload but item metadata was saved — warn the user
    // so they know to retry rather than assuming everything was backed up.
    if (result.isSuccess && result.partialFailure) {
      return 'Item backed up, but photos could not be uploaded. '
          'Check your connection and try again.';
    }

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

  Future<SyncResult> _syncDeleteItem(
    String uuid, {
    String reason = _deleteReasonDeleted,
    SyncResult? fallbackStatus,
    bool publishErrorsToStatus = true,
  }) async {
    final result = await _ref.read(syncServiceProvider).deleteRemoteItem(
          uuid,
          reason: reason,
        );
    publishSyncResult(
      _ref,
      result,
      publishErrors: publishErrorsToStatus,
      fallbackStatus: fallbackStatus,
    );
    return result;
  }

  Future<String?> _preflightCloudSync({
    required Item item,
    bool hadRemoteBackup = false,
  }) async {
    if (!item.isBackedUp) {
      return null;
    }

    if (hadRemoteBackup || _hasRemoteBackup(item)) {
      return null;
    }

    final evaluation = await _ref
        .read(cloudQuotaServiceProvider)
        .evaluatePersonalItemWrite(item);
    if (evaluation.allowedNow) {
      return null;
    }

    await _ref.read(itemRepositoryProvider).updateItem(
          item.copyWith(
            isBackedUp: false,
            clearCloudId: true,
            clearLastSyncedAt: true,
          ),
        );
    _invalidateItemLists();
    _ref.invalidate(singleItemProvider(item.uuid));
    return evaluation.message;
  }

  void _scheduleCloudSync({
    required Item item,
    bool hadRemoteBackup = false,
  }) {
    final needsDelete = !item.isBackedUp && hadRemoteBackup;
    final needsSync = item.isBackedUp;
    if (!needsDelete && !needsSync) {
      return;
    }

    final previousStatus = _ref.read(syncStatusProvider);
    _ref.read(syncStatusProvider.notifier).state = const SyncResult.syncing();
    unawaited(() async {
      if (needsDelete) {
        await _syncDeleteItem(
          item.uuid,
          reason: _deleteReasonBackupDisabled,
          fallbackStatus: previousStatus,
        );
      } else {
        await _syncItemToCloud(item, fallbackStatus: previousStatus);
      }
      _invalidateItemLists();
      _ref.invalidate(singleItemProvider(item.uuid));
    }());
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

  Future<Item> _prepareItemForUpdate(
    Item item, {
    required Item? existingItem,
  }) async {
    if (_needsItemPreparation(existingItem, item)) {
      return _prepareItem(item);
    }

    return item.copyWith(
      seasonCategory: existingItem?.seasonCategory ?? item.seasonCategory,
    );
  }

  bool _needsItemPreparation(Item? existingItem, Item nextItem) {
    if (existingItem == null) {
      return true;
    }

    return existingItem.name != nextItem.name ||
        !listEquals(existingItem.tags, nextItem.tags) ||
        !listEquals(existingItem.imagePaths, nextItem.imagePaths);
  }

  void _invalidateItemLists() {
    _ref.invalidate(allItemsProvider);
    _ref.invalidate(lentItemsProvider);
    _ref.invalidate(expiringSoonItemsProvider);
    _ref.invalidate(warrantyEndingSoonItemsProvider);
    _ref.invalidate(lendableItemsProvider);
    _ref.invalidate(forgottenItemsProvider);
    _ref.invalidate(itemTagsProvider);
    _ref.invalidate(allLocationsProvider);
    _ref.invalidate(rootLocationsProvider);
    _ref.invalidate(backedUpItemsCountProvider);
  }

  bool _isCloudQuotaExceeded(String? message) {
    final normalized = (message ?? '').toLowerCase();
    return normalized.contains('cloud quota exceeded') ||
        normalized.contains('future paid-plan item limit') ||
        normalized.contains('image-per-item limit') ||
        normalized.contains('pdf-per-item limit') ||
        normalized.contains('household cap');
  }

  bool _hasRemoteBackup(Item? item) {
    if (item == null) {
      return false;
    }

    return (item.cloudId?.trim().isNotEmpty ?? false) ||
        item.lastSyncedAt != null;
  }
}

class ArchiveItemResult {
  const ArchiveItemResult.success({this.cloudWarning}) : failureMessage = null;

  const ArchiveItemResult.failure(String message)
      : failureMessage = message,
        cloudWarning = null;

  final String? failureMessage;
  final String? cloudWarning;

  bool get hasFailure => failureMessage != null;
}

final itemsNotifierProvider =
    StateNotifierProvider<ItemsNotifier, bool>((ref) => ItemsNotifier(ref));
