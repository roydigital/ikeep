import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

import '../../core/errors/failure.dart';
import '../../core/utils/uuid_generator.dart';
import '../../domain/models/item.dart';
import '../../domain/models/item_location_history.dart';
import '../../domain/models/item_visibility.dart';
import '../database/history_dao.dart';
import '../database/item_dao.dart';
import '../database/location_dao.dart';
import '../database/pending_sync_dao.dart';
import '../../services/household_cloud_service.dart';
import '../../services/item_cloud_media_service.dart';
import 'item_repository.dart';

class ItemRepositoryImpl implements ItemRepository {
  ItemRepositoryImpl({
    required this.itemDao,
    required this.locationDao,
    required this.historyDao,
    required this.pendingSyncDao,
    required this.householdCloudService,
    required this.itemCloudMediaService,
  });

  final ItemDao itemDao;
  final LocationDao locationDao;
  final HistoryDao historyDao;
  final PendingSyncDao pendingSyncDao;
  final HouseholdCloudService householdCloudService;
  final ItemCloudMediaService itemCloudMediaService;

  static const _personalPendingSyncEntityType = 'personal_item';
  static const _householdSharedItemEntityType = 'household_shared_item';
  static const _householdSharedHistoryEntityType = 'household_shared_history';
  static const _deleteReasonDeleted = 'deleted';
  static const _deleteReasonBackupDisabled = 'backup_disabled';
  static const _deleteReasonOwnerDeleted = 'owner_deleted';
  static const _deleteReasonOwnerUnshared = 'owner_unshared';

  @override
  Future<Failure?> saveItem(
    Item item, {
    String? movedByMemberUuid,
    String? movedByName,
  }) async {
    try {
      final normalized = await _normalizeHouseholdItem(_applyCreateTimestamps(item));
      await itemDao.insertItem(normalized);

      if (_hasAssignedLocation(normalized)) {
        final history = await _buildHistoryEntry(
          item: normalized,
          movedAt: normalized.lastMovedAt ?? normalized.savedAt,
          movedByMemberUuid: movedByMemberUuid,
          movedByName: movedByName,
        );
        await historyDao.insertHistory(history);
        _trySyncHistory(history);
      }

      await locationDao.recalculateUsageCounts();
      await _queuePersonalUpsert(normalized, reason: 'save');
      _trySyncVisibility(item: normalized);
      return null;
    } on DatabaseException catch (e) {
      return Failure('Failed to save item', e);
    } on StateError catch (e) {
      return Failure(e.message, e);
    } catch (e) {
      return Failure('Failed to save item', e);
    }
  }

  @override
  Future<Failure?> updateItem(
    Item item, {
    String? movedByMemberUuid,
    String? movedByName,
  }) async {
    try {
      final existing = await itemDao.getItemByUuid(item.uuid);
      final locationChanged = _didLocationChange(existing, item);
      final normalized = await _normalizeHouseholdItem(
        _applyUpdateTimestamps(
          item,
          existing: existing,
          locationChanged: locationChanged,
        ),
      );
      final wasShared = existing?.visibility.isHousehold ?? false;
      await itemCloudMediaService.reconcileForLocalItemUpdate(
        previousItem: existing,
        nextItem: normalized,
      );

      await itemDao.updateItem(normalized);

      if (locationChanged && _hasAssignedLocation(normalized)) {
        final history = await _buildHistoryEntry(
          item: normalized,
          movedAt: normalized.lastMovedAt ?? normalized.updatedAt ?? DateTime.now(),
          movedByMemberUuid: movedByMemberUuid,
          movedByName: movedByName,
        );
        await historyDao.insertHistory(history);
        _trySyncHistory(history);
      }

      await locationDao.recalculateUsageCounts();
      if (normalized.isBackedUp) {
        await _queuePersonalUpsert(normalized, reason: 'update');
      } else if (_hasRemoteIdentity(normalized)) {
        await _queuePersonalDelete(
          itemUuid: normalized.uuid,
          itemName: normalized.name,
          reason: _deleteReasonBackupDisabled,
        );
      } else {
        await _clearQueuedPersonalSync(normalized.uuid);
      }
      _trySyncVisibility(
        item: normalized,
        removeRemote:
            wasShared && normalized.visibility == ItemVisibility.private_,
        previousHouseholdId: existing?.householdId,
      );
      return null;
    } on DatabaseException catch (e) {
      return Failure('Failed to update item', e);
    } on StateError catch (e) {
      return Failure(e.message, e);
    } catch (e) {
      return Failure('Failed to update item', e);
    }
  }

  @override
  Future<Failure?> archiveItem(String uuid) async {
    try {
      final item = await itemDao.getItemByUuid(uuid);
      if (item == null) return Failure('Item not found: $uuid');

      final archived = _applyUpdateTimestamps(
        item.copyWith(isArchived: true),
        existing: item,
        locationChanged: false,
      );
      await itemDao.updateItem(archived);
      await locationDao.recalculateUsageCounts();
      await _queuePersonalUpsert(archived, reason: 'archive');
      try {
        await _syncItemVisibility(
          item: archived,
          removeRemote: archived.visibility.isHousehold,
        );
      } catch (error) {
        if (archived.householdId != null && archived.householdId!.isNotEmpty) {
          await _queueHouseholdDelete(
            householdId: archived.householdId!,
            itemUuid: archived.uuid,
            itemName: archived.name,
            reason: _deleteReasonOwnerUnshared,
          );
        }
        debugPrint(
          'ItemRepository: archive queued household visibility after error: $error',
        );
      }
      return null;
    } catch (e) {
      return Failure('Failed to archive item', e);
    }
  }

  @override
  Future<Failure?> deleteItem(String uuid) async {
    try {
      final existing = await itemDao.getItemByUuid(uuid);
      await historyDao.deleteHistoryForItem(uuid);
      await itemCloudMediaService.deleteForItem(uuid);
      await itemDao.deleteItem(uuid);
      await locationDao.recalculateUsageCounts();
      if (existing != null && _hasRemoteIdentity(existing)) {
        await _queuePersonalDelete(
          itemUuid: existing.uuid,
          itemName: existing.name,
          reason: _deleteReasonDeleted,
        );
      } else {
        await _clearQueuedPersonalSync(uuid);
      }

      if (existing != null && existing.visibility.isHousehold) {
        final householdId = await _resolveHouseholdId(existing);
        try {
          await householdCloudService.removeSharedItem(
            householdId: householdId,
            itemUuid: uuid,
            reason: _deleteReasonOwnerDeleted,
          );
          await _clearQueuedHouseholdHistoryForItem(uuid);
          await _clearQueuedHouseholdItemSync(uuid);
        } catch (error) {
          await _queueHouseholdDelete(
            householdId: householdId,
            itemUuid: uuid,
            itemName: existing.name,
            reason: _deleteReasonOwnerDeleted,
          );
          debugPrint(
            'ItemRepository: queued household delete for $uuid after error: $error',
          );
        }
      }
      return null;
    } catch (e) {
      return Failure('Failed to delete item', e);
    }
  }

  @override
  Future<Item?> getItem(String uuid) => itemDao.getItemByUuid(uuid);

  @override
  Future<List<Item>> getAllItems({int? limit}) =>
      itemDao.getAllItems(limit: limit);

  @override
  Future<List<Item>> getItemsPage({
    required int limit,
    required int offset,
  }) =>
      itemDao.getItemsPage(limit: limit, offset: offset);

  @override
  Future<List<Item>> getItemsByLocation(String locationUuid) =>
      itemDao.getItemsByLocation(locationUuid);

  @override
  Future<List<Item>> getSharedItems({String? householdId}) =>
      itemDao.getSharedItems(householdId: householdId);

  @override
  Future<List<Item>> searchItems(String query) async {
    if (query.trim().isEmpty) return getAllItems();
    return itemDao.searchItems(query);
  }

  @override
  Future<List<Item>> getArchivedItems() => itemDao.getArchivedItems();

  Future<Item> _normalizeHouseholdItem(Item item) async {
    if (!item.visibility.isHousehold) {
      return item.copyWith(
        clearHouseholdId: true,
        sharedWithMemberUuids: const [],
      );
    }

    final householdId = await _resolveHouseholdId(item);
    return item.copyWith(householdId: householdId);
  }

  Future<String> _resolveHouseholdId(Item item) async {
    final current = item.householdId;
    if (current != null && current.isNotEmpty) return current;

    final householdId = await householdCloudService.getUserHouseholdId() ??
        await householdCloudService.ensureCurrentUserHousehold();
    if (householdId.isEmpty) {
      throw StateError('A household is required before sharing an item.');
    }
    return householdId;
  }

  Future<void> _syncItemVisibility({
    required Item item,
    bool removeRemote = false,
    String? previousHouseholdId,
  }) async {
    if (item.visibility.isHousehold && !item.isArchived) {
      final householdId = await _resolveHouseholdId(item);
      await householdCloudService.syncSharedItem(
        householdId: householdId,
        item: item.copyWith(householdId: householdId),
      );
      await _clearQueuedHouseholdItemSync(item.uuid);
      return;
    }

    if (!removeRemote) return;

    final householdId = item.householdId ?? previousHouseholdId;
    if (householdId == null || householdId.isEmpty) return;
    await householdCloudService.removeSharedItem(
      householdId: householdId,
      itemUuid: item.uuid,
      reason: _deleteReasonOwnerUnshared,
    );
    await _clearQueuedHouseholdHistoryForItem(item.uuid);
    await _clearQueuedHouseholdItemSync(item.uuid);
  }

  Future<ItemLocationHistory> _buildHistoryEntry({
    required Item item,
    required DateTime movedAt,
    String? movedByMemberUuid,
    String? movedByName,
  }) async {
    final locationUuid = item.locationUuid;
    final location = locationUuid == null
        ? null
        : await locationDao.getLocationByUuid(locationUuid);
    final locationName =
        location?.fullPath ?? location?.name ?? locationUuid ?? 'Unknown';

    return ItemLocationHistory(
      uuid: generateUuid(),
      itemUuid: item.uuid,
      locationUuid: locationUuid,
      locationName: locationName,
      movedAt: movedAt,
      movedByMemberUuid:
          movedByMemberUuid ?? householdCloudService.currentUser?.uid,
      movedByName: movedByName ?? _currentUserDisplayName(),
      userEmail: householdCloudService.currentUser?.email,
      householdId: item.householdId,
      actionDescription: 'Moved to $locationName',
    );
  }

  /// Fire-and-forget cloud sync for shared history. Errors are logged but
  /// never propagate — the local SQLite write is the source of truth.
  void _trySyncHistory(ItemLocationHistory history) {
    final householdId = history.householdId;
    if (householdId == null || householdId.isEmpty) return;
    householdCloudService
        .syncItemHistory(householdId: householdId, history: history)
        .catchError((Object e) {
      unawaited(
        _queueHouseholdHistoryUpsert(
          history: history,
          householdId: householdId,
          reason: 'item_repository_history',
        ),
      );
      debugPrint('ItemRepository: cloud history sync failed (queued): $e');
    });
  }

  /// Fire-and-forget cloud sync for item visibility. Errors are logged but
  /// never propagate — the local SQLite write is the source of truth.
  void _trySyncVisibility({
    required Item item,
    bool removeRemote = false,
    String? previousHouseholdId,
  }) {
    _syncItemVisibility(
      item: item,
      removeRemote: removeRemote,
      previousHouseholdId: previousHouseholdId,
    ).catchError((Object e) {
      final householdId = item.householdId ?? previousHouseholdId;
      if (householdId != null && householdId.isNotEmpty) {
        if (removeRemote || !item.visibility.isHousehold || item.isArchived) {
          unawaited(
            _queueHouseholdDelete(
              householdId: householdId,
              itemUuid: item.uuid,
              itemName: item.name,
              reason: _deleteReasonOwnerUnshared,
            ),
          );
        } else {
          unawaited(
            _queueHouseholdUpsert(
              item: item.copyWith(householdId: householdId),
              householdId: householdId,
              reason: 'item_repository_visibility',
            ),
          );
        }
      }
      debugPrint('ItemRepository: cloud visibility sync failed (queued): $e');
    });
  }

  String _currentUserDisplayName() {
    final user = householdCloudService.currentUser;
    final displayName = user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'You';
  }

  Item _applyCreateTimestamps(Item item) {
    final createdAt = item.savedAt;
    final hasLocation = _hasAssignedLocation(item);
    return item.copyWith(
      updatedAt: item.updatedAt ?? createdAt,
      lastUpdatedAt: item.lastUpdatedAt,
      lastMovedAt: hasLocation ? (item.lastMovedAt ?? createdAt) : item.lastMovedAt,
    );
  }

  Item _applyUpdateTimestamps(
    Item item, {
    required Item? existing,
    required bool locationChanged,
  }) {
    final now = DateTime.now();
    return item.copyWith(
      updatedAt: now,
      lastUpdatedAt:
          locationChanged ? (existing?.lastUpdatedAt ?? item.lastUpdatedAt) : now,
      lastMovedAt:
          locationChanged ? now : (existing?.lastMovedAt ?? item.lastMovedAt),
    );
  }

  bool _didLocationChange(Item? existing, Item next) {
    if (existing == null) {
      return _hasAssignedLocation(next);
    }

    return existing.locationUuid != next.locationUuid ||
        existing.areaUuid != next.areaUuid ||
        existing.roomUuid != next.roomUuid ||
        existing.zoneUuid != next.zoneUuid;
  }

  bool _hasAssignedLocation(Item item) {
    return (item.zoneUuid?.isNotEmpty ?? false) ||
        (item.locationUuid?.isNotEmpty ?? false);
  }

  bool _hasRemoteIdentity(Item item) {
    return (item.cloudId?.trim().isNotEmpty ?? false) ||
        item.lastSyncedAt != null;
  }

  Future<void> _queuePersonalUpsert(
    Item item, {
    required String reason,
  }) async {
    if (!item.isBackedUp) {
      await _clearQueuedPersonalSync(item.uuid);
      return;
    }

    try {
      await pendingSyncDao.enqueue(
        operationType: 'upsert',
        entityType: _personalPendingSyncEntityType,
        entityUuid: item.uuid,
        payload: {
          'itemUuid': item.uuid,
          'itemName': item.name,
          'reason': reason,
          'isBackedUp': item.isBackedUp,
          'hasRemoteIdentity': _hasRemoteIdentity(item),
          'updatedAt': item.updatedAt?.toIso8601String(),
          'lastMovedAt': item.lastMovedAt?.toIso8601String(),
          'lastSyncedAt': item.lastSyncedAt?.toIso8601String(),
        },
      );
      debugPrint(
        'ItemRepository: queued personal upsert ${item.uuid} reason=$reason',
      );
    } catch (error) {
      debugPrint(
        'ItemRepository: failed to queue personal upsert ${item.uuid}: $error',
      );
    }
  }

  Future<void> _queuePersonalDelete({
    required String itemUuid,
    required String itemName,
    required String reason,
  }) async {
    try {
      await pendingSyncDao.enqueue(
        operationType: 'delete',
        entityType: _personalPendingSyncEntityType,
        entityUuid: itemUuid,
        payload: {
          'itemUuid': itemUuid,
          'itemName': itemName,
          'reason': reason,
          'hadRemoteIdentity': true,
        },
      );
      debugPrint(
        'ItemRepository: queued personal delete $itemUuid reason=$reason',
      );
    } catch (error) {
      debugPrint(
        'ItemRepository: failed to queue personal delete $itemUuid: $error',
      );
    }
  }

  Future<void> _clearQueuedPersonalSync(String itemUuid) async {
    try {
      await pendingSyncDao.deleteByEntity(
        entityType: _personalPendingSyncEntityType,
        entityUuid: itemUuid,
      );
    } catch (error) {
      debugPrint(
        'ItemRepository: failed to clear queued personal sync '
        '$itemUuid: $error',
      );
    }
  }

  Future<void> _queueHouseholdUpsert({
    required Item item,
    required String householdId,
    required String reason,
  }) async {
    try {
      await pendingSyncDao.enqueue(
        operationType: 'upsert',
        entityType: _householdSharedItemEntityType,
        entityUuid: item.uuid,
        payload: {
          'householdId': householdId,
          'itemUuid': item.uuid,
          'itemName': item.name,
          'reason': reason,
          'item': item.toJson(),
        },
      );
    } catch (error) {
      debugPrint(
        'ItemRepository: failed to queue household upsert ${item.uuid}: $error',
      );
    }
  }

  Future<void> _queueHouseholdDelete({
    required String householdId,
    required String itemUuid,
    required String itemName,
    required String reason,
  }) async {
    try {
      await pendingSyncDao.enqueue(
        operationType: 'delete',
        entityType: _householdSharedItemEntityType,
        entityUuid: itemUuid,
        payload: {
          'householdId': householdId,
          'itemUuid': itemUuid,
          'itemName': itemName,
          'reason': reason,
        },
      );
    } catch (error) {
      debugPrint(
        'ItemRepository: failed to queue household delete $itemUuid: $error',
      );
    }
  }

  Future<void> _queueHouseholdHistoryUpsert({
    required ItemLocationHistory history,
    required String householdId,
    required String reason,
  }) async {
    try {
      await pendingSyncDao.enqueue(
        operationType: 'upsert',
        entityType: _householdSharedHistoryEntityType,
        entityUuid: history.uuid,
        payload: {
          'householdId': householdId,
          'reason': reason,
          'history': history.toJson(),
        },
      );
    } catch (error) {
      debugPrint(
        'ItemRepository: failed to queue household history ${history.uuid}: $error',
      );
    }
  }

  Future<void> _clearQueuedHouseholdItemSync(String itemUuid) async {
    try {
      await pendingSyncDao.deleteByEntity(
        entityType: _householdSharedItemEntityType,
        entityUuid: itemUuid,
      );
    } catch (error) {
      debugPrint(
        'ItemRepository: failed to clear queued household sync '
        '$itemUuid: $error',
      );
    }
  }

  Future<void> _clearQueuedHouseholdHistoryForItem(String itemUuid) async {
    try {
      final queuedHistoryOps =
          await pendingSyncDao.getByEntityType(_householdSharedHistoryEntityType);
      for (final operation in queuedHistoryOps) {
        final historyPayload = operation.payload['history'];
        if (historyPayload is! Map) {
          continue;
        }
        final rawItemId =
            historyPayload['itemId'] ?? historyPayload['itemUuid'];
        if (rawItemId == itemUuid) {
          await pendingSyncDao.deleteById(operation.id);
        }
      }
    } catch (error) {
      debugPrint(
        'ItemRepository: failed to clear queued household history '
        '$itemUuid: $error',
      );
    }
  }
}
