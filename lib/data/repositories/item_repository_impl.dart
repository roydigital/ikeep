import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/errors/failure.dart';
import '../../core/utils/uuid_generator.dart';
import '../../domain/models/item.dart';
import '../../domain/models/item_location_history.dart';
import '../../domain/models/item_visibility.dart';
import '../database/history_dao.dart';
import '../database/item_dao.dart';
import '../database/location_dao.dart';
import '../../services/household_cloud_service.dart';
import 'item_repository.dart';

class ItemRepositoryImpl implements ItemRepository {
  ItemRepositoryImpl({
    required this.itemDao,
    required this.locationDao,
    required this.historyDao,
    required this.householdCloudService,
  });

  final ItemDao itemDao;
  final LocationDao locationDao;
  final HistoryDao historyDao;
  final HouseholdCloudService householdCloudService;

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
      await _syncItemVisibility(
          item: archived, removeRemote: archived.visibility.isHousehold);
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
      await itemDao.deleteItem(uuid);
      await locationDao.recalculateUsageCounts();

      if (existing != null && existing.visibility.isHousehold) {
        final householdId = await _resolveHouseholdId(existing);
        await householdCloudService.removeSharedItem(
          householdId: householdId,
          itemUuid: uuid,
        );
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
      return;
    }

    if (!removeRemote) return;

    final householdId = item.householdId ?? previousHouseholdId;
    if (householdId == null || householdId.isEmpty) return;
    await householdCloudService.removeSharedItem(
      householdId: householdId,
      itemUuid: item.uuid,
    );
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
}
