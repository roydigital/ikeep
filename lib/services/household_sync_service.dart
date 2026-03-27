import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/database/history_dao.dart';
import '../data/database/item_dao.dart';
import '../data/database/pending_sync_dao.dart';
import '../data/database/sync_checkpoint_dao.dart';
import '../domain/models/item.dart';
import '../domain/models/item_cloud_media_reference.dart';
import '../domain/models/item_location_history.dart';
import '../domain/models/item_visibility.dart';
import '../domain/models/sync_checkpoint_state.dart';
import '../domain/models/sync_status.dart';
import 'cloud_observation_service.dart';
import 'household_cloud_service.dart';
import 'item_cloud_media_service.dart';

class HouseholdSyncService {
  HouseholdSyncService({
    required FirebaseAuth auth,
    required ItemDao itemDao,
    required HistoryDao historyDao,
    required PendingSyncDao pendingSyncDao,
    required SyncCheckpointDao syncCheckpointDao,
    required HouseholdCloudService householdCloudService,
    required ItemCloudMediaService itemCloudMediaService,
    required CloudObservationService cloudObservationService,
  })  : _auth = auth,
        _itemDao = itemDao,
        _historyDao = historyDao,
        _pendingSyncDao = pendingSyncDao,
        _syncCheckpointDao = syncCheckpointDao,
        _householdCloudService = householdCloudService,
        _itemCloudMediaService = itemCloudMediaService,
        _cloudObservationService = cloudObservationService;

  final FirebaseAuth _auth;
  final ItemDao _itemDao;
  final HistoryDao _historyDao;
  final PendingSyncDao _pendingSyncDao;
  final SyncCheckpointDao _syncCheckpointDao;
  final HouseholdCloudService _householdCloudService;
  final ItemCloudMediaService _itemCloudMediaService;
  final CloudObservationService _cloudObservationService;
  final StreamController<void> _localChangesController =
      StreamController<void>.broadcast();

  String? _activeHouseholdId;
  bool _isSyncRunning = false;

  static const _sharedScopePrefix = 'household_shared';
  static const _sharedItemEntityType = 'household_shared_item';
  static const _sharedHistoryEntityType = 'household_shared_history';
  static const _deleteReasonOwnerDeleted = 'owner_deleted';
  static const _deleteReasonOwnerUnshared = 'owner_unshared';
  static const _deltaCheckpointMaxAge = Duration(days: 7);
  static const _sharedTombstoneRetention = Duration(days: 45);

  bool get isRunning => _activeHouseholdId != null;
  Stream<void> get localChanges => _localChangesController.stream;

  Future<SyncResult> startSync(String householdId) async {
    if (householdId.trim().isEmpty) {
      return const SyncResult.error('Household id is required');
    }
    if (_isSyncRunning) {
      return const SyncResult.syncing();
    }

    _activeHouseholdId = householdId;
    _isSyncRunning = true;
    SyncResult? result;

    try {
      final accessState =
          await _householdCloudService.getAccessState(householdId);
      if (accessState.accessLost) {
        await _handleMembershipLoss(
          householdId: householdId,
          reason: 'membership_lost',
        );
        await _clearCheckpoint(householdId);
        await stopSync();
        result = SyncResult.success();
        return result;
      }

      final checkpoint = await _loadCheckpoint(householdId);
      final fallbackReason = _fallbackReasonForCheckpoint(
        checkpoint: checkpoint,
        accessState: accessState,
      );
      if (fallbackReason != null) {
        result = await _runFullSync(
          householdId: householdId,
          accessState: accessState,
          reason: fallbackReason,
        );
        return result;
      }

      try {
        result = await _runDeltaSync(
          householdId: householdId,
          checkpoint: checkpoint!,
        );
        return result;
      } on _HouseholdDeltaFallbackException catch (error) {
        result = await _runFullSync(
          householdId: householdId,
          accessState: accessState,
          reason: error.reason,
        );
        return result;
      } catch (error, stackTrace) {
        debugPrint(
          '[IkeepHouseholdDelta] delta sync exception '
          'household=$householdId error=$error\n$stackTrace',
        );
        result = await _runFullSync(
          householdId: householdId,
          accessState: accessState,
          reason: 'delta_exception',
        );
        return result;
      }
    } finally {
      _isSyncRunning = false;
      if (_shouldObserveSyncResult(result)) {
        await _observeSyncRun(
          source: 'household_start_sync:$householdId',
          result: result!,
        );
      }
    }
  }

  Future<SyncResult> fullSync(String householdId) async {
    final accessState =
        await _householdCloudService.getAccessState(householdId);
    final result = await _runFullSync(
      householdId: householdId,
      accessState: accessState,
      reason: 'manual_full_sync',
    );
    if (_shouldObserveSyncResult(result)) {
      await _observeSyncRun(
        source: 'household_full_sync:$householdId',
        result: result,
      );
    }
    return result;
  }

  Future<void> stopSync() async {
    _activeHouseholdId = null;
  }

  Future<SyncResult> syncLocalItemChange(Item item) async {
    if (!item.visibility.isHousehold) {
      return _syncItemDeletion(
        itemUuid: item.uuid,
        householdId: item.householdId,
        reason: _deleteReasonOwnerUnshared,
      );
    }

    final householdId = item.householdId ?? _activeHouseholdId;
    if (householdId == null || householdId.isEmpty) {
      return const SyncResult.error(
        'A household is required before syncing shared items.',
      );
    }

    try {
      await _householdCloudService.syncSharedItem(
        householdId: householdId,
        item: item.copyWith(householdId: householdId),
      );
      await _clearQueuedSharedItemSync(item.uuid);
      return SyncResult.success();
    } catch (error) {
      await _queueSharedItemUpsert(
        item: item.copyWith(householdId: householdId),
        householdId: householdId,
        reason: 'sync_local_item_change',
      );
      return SyncResult.error('Queued shared item sync: $error');
    }
  }

  Future<SyncResult> syncLocalHistoryChange(ItemLocationHistory history) async {
    final householdId = history.householdId ?? _activeHouseholdId;
    if (householdId == null || householdId.isEmpty) {
      return const SyncResult.error(
        'A household is required before syncing shared history.',
      );
    }

    try {
      await _householdCloudService.syncItemHistory(
        householdId: householdId,
        history: history,
      );
      await _pendingSyncDao.deleteByEntity(
        entityType: _sharedHistoryEntityType,
        entityUuid: history.uuid,
      );
      return SyncResult.success();
    } catch (error) {
      await _queueSharedHistoryUpsert(
        history: history,
        householdId: householdId,
        reason: 'sync_local_history_change',
      );
      return SyncResult.error('Queued shared history sync: $error');
    }
  }

  Future<SyncResult> syncLocalDeletion({
    required String itemUuid,
    String? householdId,
    String reason = _deleteReasonOwnerDeleted,
  }) async {
    return _syncItemDeletion(
      itemUuid: itemUuid,
      householdId: householdId,
      reason: reason,
    );
  }

  Future<void> flushPendingOperations() async {
    final householdId = _activeHouseholdId;
    if (householdId == null || householdId.isEmpty) {
      return;
    }
    await _pushLocalSharedDeltas(householdId: householdId);
  }

  Future<SyncResult> _runDeltaSync({
    required String householdId,
    required SyncCheckpointState checkpoint,
  }) async {
    final pullOutcome = await _pullRemoteSharedItemDeltas(
      householdId: householdId,
      checkpoint: checkpoint,
    );
    final pushOutcome = await _pushLocalSharedDeltas(householdId: householdId);

    final pulledChanges = pullOutcome.importedCount +
        pullOutcome.deletedCount +
        pullOutcome.unsharedCount +
        pullOutcome.membershipConvertedCount;
    if (pushOutcome.shouldClearCheckpoint) {
      await _clearCheckpoint(householdId);
      return SyncResult.success(
        partialFailure: pushOutcome.failedItems > 0,
        totalItems: pulledChanges,
        syncedItems: pulledChanges,
        failedItems: pushOutcome.failedItems,
        itemOutcomes: pushOutcome.itemOutcomes,
      );
    }

    final now = DateTime.now().toUtc();
    final remoteCheckpoint =
        await _householdCloudService.fetchLatestSharedRemoteCheckpoint(
              householdId,
            ) ??
            checkpoint.lastKnownRemoteCheckpoint;
    final nextCheckpoint = checkpoint.copyWith(
      householdId: householdId,
      lastSuccessfulPullAt:
          pullOutcome.success ? now : checkpoint.lastSuccessfulPullAt,
      lastSuccessfulPushAt:
          pushOutcome.success ? now : checkpoint.lastSuccessfulPushAt,
      lastKnownRemoteCheckpoint: remoteCheckpoint,
      updatedAt: now,
    );
    await _saveCheckpoint(nextCheckpoint);
    await _cleanupSharedTombstonesIfSafe(
      householdId: householdId,
      checkpoint: nextCheckpoint,
    );

    final totalItems = pulledChanges +
        pushOutcome.syncedItems +
        pushOutcome.deletedItems +
        pushOutcome.historyOps;

    return SyncResult.success(
      partialFailure: pushOutcome.failedItems > 0,
      totalItems: totalItems,
      syncedItems:
          pulledChanges + pushOutcome.syncedItems + pushOutcome.historyOps,
      failedItems: pushOutcome.failedItems,
      itemOutcomes: pushOutcome.itemOutcomes,
    );
  }

  Future<SyncResult> _runFullSync({
    required String householdId,
    required HouseholdAccessState accessState,
    required String reason,
  }) async {
    debugPrint(
      '[IkeepHouseholdDelta] falling back to full sync '
      'household=$householdId reason=$reason',
    );

    if (accessState.accessLost) {
      await _handleMembershipLoss(
        householdId: householdId,
        reason: 'membership_lost_full_sync',
      );
      await _clearCheckpoint(householdId);
      await stopSync();
      return SyncResult.success();
    }

    if (accessState.accessUncertain) {
      final refreshedAccess = await _householdCloudService.getAccessState(
        householdId,
      );
      if (refreshedAccess.accessLost) {
        await _handleMembershipLoss(
          householdId: householdId,
          reason: 'membership_lost_refreshed',
        );
        await _clearCheckpoint(householdId);
        await stopSync();
        return SyncResult.success();
      }
      if (refreshedAccess.accessUncertain) {
        await stopSync();
        return const SyncResult.error(
          'Household membership or permissions are uncertain; skipped risky shared-item sync.',
        );
      }
    }

    final results = await Future.wait([
      _householdCloudService.fetchAllSharedItemDocs(householdId),
      _householdCloudService.fetchAllSharedItemTombstones(householdId),
    ]);
    final sharedItemSnapshot =
        results[0] as QuerySnapshot<Map<String, dynamic>>;
    final tombstoneSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;

    final remoteItemIds = <String>{};
    final tombstonedItemIds = <String>{};
    final events = <_HouseholdRemoteDeltaEvent>[];

    for (final doc in sharedItemSnapshot.docs) {
      final data = doc.data();
      final itemUuid = ((data['uuid'] as String?) ?? doc.id).trim();
      final changedAt =
          _householdCloudService.resolveSharedItemChangedAt(data) ??
              DateTime.fromMillisecondsSinceEpoch(0);
      if (itemUuid.isEmpty) {
        continue;
      }
      remoteItemIds.add(itemUuid);
      events.add(
        _HouseholdRemoteDeltaEvent.item(
          itemUuid: itemUuid,
          changedAt: changedAt,
          data: data,
        ),
      );
    }

    for (final doc in tombstoneSnapshot.docs) {
      final data = doc.data();
      var tombstone = _remoteSharedTombstoneFromData(doc.id, data);
      tombstone ??= _HouseholdRemoteTombstone(
        itemUuid: ((data['itemUuid'] as String?) ?? doc.id).trim(),
        ownerUid: (data['ownerUid'] as String?)?.trim(),
        reason: ((data['reason'] as String?)?.trim().isNotEmpty ?? false)
            ? (data['reason'] as String).trim()
            : _deleteReasonOwnerDeleted,
        changedAt:
            _householdCloudService.resolveSharedTombstoneChangedAt(data) ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );
      if (tombstone.itemUuid.isEmpty) {
        continue;
      }
      tombstonedItemIds.add(tombstone.itemUuid);
      events.add(_HouseholdRemoteDeltaEvent.tombstone(tombstone: tombstone));
    }

    events.sort((a, b) => a.changedAt.compareTo(b.changedAt));

    var importedCount = 0;
    var deletedCount = 0;
    var unsharedCount = 0;
    for (final event in events) {
      if (event.tombstone != null) {
        final outcome = await _applyRemoteSharedTombstone(
          tombstone: event.tombstone!,
          source: 'full_sync',
        );
        if (outcome.deletedLocally) {
          deletedCount++;
        }
        if (outcome.convertedToPrivate) {
          unsharedCount++;
        }
        continue;
      }

      final changed = await _applyRemoteSharedItemData(
        householdId: householdId,
        itemUuid: event.itemUuid,
        data: event.data!,
      );
      if (changed) {
        importedCount++;
      }
    }

    final localSharedItems =
        await _itemDao.getSharedItems(householdId: householdId);
    for (final localItem in localSharedItems) {
      if (remoteItemIds.contains(localItem.uuid) ||
          tombstonedItemIds.contains(localItem.uuid)) {
        continue;
      }

      final convertedToPrivate =
          await _removeMissingRemoteSharedItem(localItem);
      if (convertedToPrivate) {
        unsharedCount++;
      } else {
        deletedCount++;
      }
    }

    final pushOutcome = await _pushLocalSharedDeltas(householdId: householdId);
    if (pushOutcome.shouldClearCheckpoint) {
      await _clearCheckpoint(householdId);
      return SyncResult.success(
        partialFailure: pushOutcome.failedItems > 0,
        totalItems: importedCount + deletedCount + unsharedCount,
        syncedItems: importedCount + deletedCount + unsharedCount,
        failedItems: pushOutcome.failedItems,
        itemOutcomes: pushOutcome.itemOutcomes,
      );
    }
    final now = DateTime.now().toUtc();
    final fullSyncRemoteCheckpoint =
        await _householdCloudService.fetchLatestSharedRemoteCheckpoint(
              householdId,
              allowCompatibilityScan: true,
            ) ??
            (events.isNotEmpty
                ? events.last.changedAt.toUtc().toIso8601String()
                : null);
    final nextCheckpoint = SyncCheckpointState(
      syncScope: _scopeForHousehold(householdId),
      householdId: householdId,
      lastSuccessfulPullAt: now,
      lastSuccessfulPushAt: pushOutcome.success ? now : null,
      lastFullSyncAt: now,
      lastKnownRemoteCheckpoint: fullSyncRemoteCheckpoint,
      updatedAt: now,
    );
    await _saveCheckpoint(nextCheckpoint);
    await _cleanupSharedTombstonesIfSafe(
      householdId: householdId,
      checkpoint: nextCheckpoint,
    );

    return SyncResult.success(
      partialFailure: pushOutcome.failedItems > 0,
      totalItems: importedCount +
          deletedCount +
          unsharedCount +
          pushOutcome.syncedItems +
          pushOutcome.deletedItems +
          pushOutcome.historyOps,
      syncedItems: importedCount +
          deletedCount +
          unsharedCount +
          pushOutcome.syncedItems +
          pushOutcome.deletedItems +
          pushOutcome.historyOps,
      failedItems: pushOutcome.failedItems,
      itemOutcomes: pushOutcome.itemOutcomes,
    );
  }

  Future<_HouseholdDeltaPullOutcome> _pullRemoteSharedItemDeltas({
    required String householdId,
    required SyncCheckpointState checkpoint,
  }) async {
    final remoteCursor = checkpoint.lastKnownRemoteCheckpoint?.trim();
    final changedAfter = remoteCursor == null || remoteCursor.isEmpty
        ? null
        : DateTime.tryParse(remoteCursor)?.toUtc();
    if (changedAfter == null) {
      throw const _HouseholdDeltaFallbackException('invalid_remote_checkpoint');
    }

    final results = await Future.wait([
      _householdCloudService.fetchSharedItemsChangedSince(
        householdId: householdId,
        changedAfter: changedAfter,
      ),
      _householdCloudService.fetchSharedItemTombstonesChangedSince(
        householdId: householdId,
        changedAfter: changedAfter,
      ),
    ]);

    final sharedItemSnapshot =
        results[0] as QuerySnapshot<Map<String, dynamic>>;
    final tombstoneSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final events = <_HouseholdRemoteDeltaEvent>[];

    for (final doc in sharedItemSnapshot.docs) {
      final data = doc.data();
      final itemUuid = ((data['uuid'] as String?) ?? doc.id).trim();
      final changedAt = _householdCloudService.resolveSharedItemChangedAt(data);
      if (itemUuid.isEmpty || changedAt == null) {
        throw const _HouseholdDeltaFallbackException(
          'shared_item_schema_mismatch',
        );
      }
      events.add(
        _HouseholdRemoteDeltaEvent.item(
          itemUuid: itemUuid,
          changedAt: changedAt,
          data: data,
        ),
      );
    }

    for (final doc in tombstoneSnapshot.docs) {
      final tombstone = _remoteSharedTombstoneFromData(doc.id, doc.data());
      if (tombstone == null) {
        throw const _HouseholdDeltaFallbackException(
          'shared_tombstone_schema_mismatch',
        );
      }
      events.add(_HouseholdRemoteDeltaEvent.tombstone(tombstone: tombstone));
    }

    events.sort((a, b) => a.changedAt.compareTo(b.changedAt));
    debugPrint(
      '[IkeepHouseholdDelta] delta pull '
      'household=$householdId items=${sharedItemSnapshot.docs.length} '
      'tombstones=${tombstoneSnapshot.docs.length} since=$remoteCursor',
    );

    var importedCount = 0;
    var deletedCount = 0;
    var unsharedCount = 0;
    var membershipConvertedCount = 0;

    for (final event in events) {
      if (event.tombstone != null) {
        final outcome = await _applyRemoteSharedTombstone(
          tombstone: event.tombstone!,
          source: 'delta_pull',
        );
        if (outcome.deletedLocally) {
          deletedCount++;
        }
        if (outcome.convertedToPrivate) {
          unsharedCount++;
        }
        if (outcome.convertedMembershipLocally) {
          membershipConvertedCount++;
        }
        continue;
      }

      final changed = await _applyRemoteSharedItemData(
        householdId: householdId,
        itemUuid: event.itemUuid,
        data: event.data!,
      );
      if (changed) {
        importedCount++;
      }
    }

    return _HouseholdDeltaPullOutcome(
      success: true,
      importedCount: importedCount,
      deletedCount: deletedCount,
      unsharedCount: unsharedCount,
      membershipConvertedCount: membershipConvertedCount,
    );
  }

  Future<_HouseholdDeltaPushOutcome> _pushLocalSharedDeltas({
    required String householdId,
  }) async {
    final accessState =
        await _householdCloudService.getAccessState(householdId);
    if (accessState.accessLost) {
      final droppedOps = await _dropQueuedSharedOpsForHousehold(
        householdId: householdId,
        reason: 'membership_lost_before_replay',
      );
      await _handleMembershipLoss(
        householdId: householdId,
        reason: 'membership_lost_before_replay',
      );
      await _clearCheckpoint(householdId);
      await stopSync();
      return _HouseholdDeltaPushOutcome(
        success: true,
        syncedItems: 0,
        deletedItems: 0,
        historyOps: 0,
        skippedItems: droppedOps,
        failedItems: 0,
        itemOutcomes: const [],
        shouldClearCheckpoint: true,
      );
    }
    if (accessState.accessUncertain) {
      debugPrint(
        '[IkeepHouseholdDelta] replay skipped '
        'household=$householdId reason=uncertain_membership_or_permissions',
      );
      await _clearCheckpoint(householdId);
      return const _HouseholdDeltaPushOutcome(
        success: false,
        syncedItems: 0,
        deletedItems: 0,
        historyOps: 0,
        skippedItems: 0,
        failedItems: 0,
        itemOutcomes: [],
        shouldClearCheckpoint: true,
      );
    }

    final localSharedItems =
        await _itemDao.getSharedItems(householdId: householdId);
    final localSharedItemsByUuid = {
      for (final item in localSharedItems) item.uuid: item,
    };
    final queuedItemOps =
        await _pendingSyncDao.getByEntityType(_sharedItemEntityType);
    final queuedHistoryOps =
        await _pendingSyncDao.getByEntityType(_sharedHistoryEntityType);

    final itemsToUpsert = <String, Item>{};
    final itemsToDelete = <String, _HouseholdDeleteRequest>{};
    final historiesToUpsert = <PendingSyncOperation>[];
    final queuedItemUuids = <String>{};
    final remoteStateCache = <String, HouseholdSharedItemRemoteState>{};

    var skippedItems = 0;
    var queueSelectedPushes = 0;
    var queueSelectedDeletes = 0;
    var timestampFallbackPushes = 0;

    Future<HouseholdSharedItemRemoteState> loadRemoteState(
        String itemUuid) async {
      final cachedState = remoteStateCache[itemUuid];
      if (cachedState != null) {
        return cachedState;
      }
      final loadedState =
          await _householdCloudService.fetchSharedItemRemoteState(
        householdId: householdId,
        itemUuid: itemUuid,
      );
      remoteStateCache[itemUuid] = loadedState;
      return loadedState;
    }

    for (final operation in queuedItemOps) {
      final operationHouseholdId =
          (operation.payload['householdId'] as String?)?.trim();
      if (operationHouseholdId != householdId) {
        continue;
      }

      queuedItemUuids.add(operation.entityUuid);
      if (operation.operationType == 'delete') {
        final reason = (operation.payload['reason'] as String?) ??
            _deleteReasonOwnerDeleted;
        itemsToDelete[operation.entityUuid] = _HouseholdDeleteRequest(
          itemUuid: operation.entityUuid,
          itemName: (operation.payload['itemName'] as String?) ??
              operation.entityUuid,
          reason: reason,
          queueId: operation.id,
        );
        queueSelectedDeletes++;
        debugPrint(
          '[IkeepHouseholdDelta] queue-selected delete '
          'household=$householdId item=${operation.entityUuid} reason=$reason',
        );
        continue;
      }

      final localItem = localSharedItemsByUuid[operation.entityUuid];
      if (localItem == null) {
        await _pendingSyncDao.deleteById(operation.id);
        skippedItems++;
        continue;
      }
      itemsToUpsert[localItem.uuid] = localItem;
      queueSelectedPushes++;
      debugPrint(
        '[IkeepHouseholdDelta] queue-selected upsert '
        'household=$householdId item=${localItem.uuid}',
      );
    }

    for (final operation in queuedHistoryOps) {
      final operationHouseholdId =
          (operation.payload['householdId'] as String?)?.trim();
      if (operationHouseholdId != householdId) {
        continue;
      }
      final historyItemUuid = _historyItemUuidFromOperation(operation);
      if (historyItemUuid == null ||
          historyItemUuid.isEmpty ||
          itemsToDelete.containsKey(historyItemUuid) ||
          !localSharedItemsByUuid.containsKey(historyItemUuid)) {
        await _pendingSyncDao.deleteById(operation.id);
        debugPrint(
          '[IkeepHouseholdDelta] dropped stale queued history '
          'household=$householdId history=${operation.entityUuid} '
          'item=$historyItemUuid',
        );
        continue;
      }
      historiesToUpsert.add(operation);
    }

    for (final item in localSharedItems) {
      if (queuedItemUuids.contains(item.uuid)) {
        continue;
      }
      if (_localSharedItemNeedsPush(item)) {
        itemsToUpsert[item.uuid] = item;
        timestampFallbackPushes++;
        debugPrint(
          '[IkeepHouseholdDelta] timestamp-selected upsert '
          'household=$householdId item=${item.uuid}',
        );
      } else {
        skippedItems++;
      }
    }

    debugPrint(
      '[IkeepHouseholdDelta] delta push plan '
      'household=$householdId queuePush=$queueSelectedPushes '
      'queueDelete=$queueSelectedDeletes '
      'timestampPush=$timestampFallbackPushes '
      'historyOps=${historiesToUpsert.length} skipped=$skippedItems',
    );

    var syncedItems = 0;
    var deletedItems = 0;
    var historyOps = 0;
    var failedItems = 0;
    final itemOutcomes = <ItemSyncOutcome>[];

    for (final request in itemsToDelete.values) {
      final remoteState = await loadRemoteState(request.itemUuid);
      final replayDecision = _sharedDeleteReplayDecision(
        request: request,
        localItem: localSharedItemsByUuid[request.itemUuid],
        remoteState: remoteState,
      );
      if (!replayDecision.proceed) {
        if (replayDecision.applyRemoteTombstone != null) {
          await _applyRemoteSharedTombstone(
            tombstone: replayDecision.applyRemoteTombstone!,
            source: 'queue_delete_drop',
          );
        }
        if (request.queueId != null) {
          await _pendingSyncDao.deleteById(request.queueId!);
        }
        await _clearQueuedSharedHistoryForItem(request.itemUuid);
        skippedItems++;
        debugPrint(
          '[IkeepHouseholdDelta] dropped queued delete '
          'household=$householdId item=${request.itemUuid} '
          'reason=${replayDecision.reason}',
        );
        continue;
      }

      try {
        await _householdCloudService.removeSharedItem(
          householdId: householdId,
          itemUuid: request.itemUuid,
          reason: request.reason,
        );
        await _clearQueuedSharedHistoryForItem(request.itemUuid);
        if (request.queueId != null) {
          await _pendingSyncDao.deleteById(request.queueId!);
        }
        deletedItems++;
        itemOutcomes.add(ItemSyncOutcome(
          itemUuid: request.itemUuid,
          itemName: request.itemName,
          success: true,
        ));
      } catch (error) {
        failedItems++;
        itemOutcomes.add(ItemSyncOutcome(
          itemUuid: request.itemUuid,
          itemName: request.itemName,
          success: false,
          errorMessage: error.toString(),
        ));
      }
    }

    for (final item in itemsToUpsert.values) {
      final remoteState = await loadRemoteState(item.uuid);
      final replayDecision = _sharedItemUpsertReplayDecision(
        item: item,
        remoteState: remoteState,
      );
      if (!replayDecision.proceed) {
        if (replayDecision.applyRemoteTombstone != null) {
          await _applyRemoteSharedTombstone(
            tombstone: replayDecision.applyRemoteTombstone!,
            source: 'queue_upsert_drop',
          );
        }
        await _clearQueuedSharedItemSync(item.uuid);
        skippedItems++;
        debugPrint(
          '[IkeepHouseholdDelta] dropped queued upsert '
          'household=$householdId item=${item.uuid} '
          'reason=${replayDecision.reason}',
        );
        continue;
      }

      var replayItem = item.copyWith(householdId: householdId);
      try {
        if (replayDecision.memberLocationOnly) {
          final remoteData = remoteState.itemData;
          if (remoteData != null) {
            final remoteReplayItem = _sharedItemDocToLocalItem(
              householdId: householdId,
              itemId: item.uuid,
              data: remoteData,
            );
            final sanitizedItem = _sanitizeMemberReplayItem(
              localItem: replayItem,
              remoteItem: remoteReplayItem,
            );
            if (_memberHasUnauthorizedContentDrift(
                  localItem: replayItem,
                  remoteItem: remoteReplayItem,
                ) ||
                _localImageMediaDirty(
                  imagePaths: replayItem.imagePaths,
                  existingReferences: await _itemCloudMediaService
                      .getImageReferencesForItem(replayItem.uuid),
                ) ||
                _localInvoiceMediaDirty(
                  invoicePath: replayItem.invoicePath,
                  existingReference: await _itemCloudMediaService
                      .getInvoiceReferenceForItem(replayItem.uuid),
                )) {
              await _itemDao.updateItem(sanitizedItem);
              await _itemCloudMediaService.replaceForItemFromCloudData(
                itemUuid: item.uuid,
                data: remoteData,
              );
              localSharedItemsByUuid[item.uuid] = sanitizedItem;
              replayItem = sanitizedItem;
              _notifyLocalChange();
              debugPrint(
                '[IkeepHouseholdDelta] sanitized member replay item '
                'household=$householdId item=${item.uuid}',
              );
            }
          }
          debugPrint(
            '[IkeepHouseholdDelta] member replay limited to location/history '
            'household=$householdId item=${item.uuid}',
          );
        }
        await _householdCloudService.syncSharedItem(
          householdId: householdId,
          item: replayItem,
        );
        await _clearQueuedSharedItemSync(replayItem.uuid);
        syncedItems++;
        itemOutcomes.add(ItemSyncOutcome(
          itemUuid: replayItem.uuid,
          itemName: replayItem.name,
          success: true,
        ));
      } catch (error) {
        failedItems++;
        itemOutcomes.add(ItemSyncOutcome(
          itemUuid: replayItem.uuid,
          itemName: replayItem.name,
          success: false,
          errorMessage: error.toString(),
        ));
      }
    }

    for (final operation in historiesToUpsert) {
      try {
        final historyPayload = Map<String, dynamic>.from(
          operation.payload['history'] as Map,
        );
        final history = ItemLocationHistory.fromJson(historyPayload);
        final remoteState = await loadRemoteState(history.itemUuid);
        final replayDecision = _sharedHistoryReplayDecision(
          history: history,
          localItem: localSharedItemsByUuid[history.itemUuid],
          remoteState: remoteState,
        );
        if (!replayDecision.proceed) {
          if (replayDecision.applyRemoteTombstone != null) {
            await _applyRemoteSharedTombstone(
              tombstone: replayDecision.applyRemoteTombstone!,
              source: 'queue_history_drop',
            );
          }
          await _pendingSyncDao.deleteById(operation.id);
          skippedItems++;
          debugPrint(
            '[IkeepHouseholdDelta] dropped queued history '
            'household=$householdId history=${operation.entityUuid} '
            'item=${history.itemUuid} reason=${replayDecision.reason}',
          );
          continue;
        }
        await _householdCloudService.syncItemHistory(
          householdId: householdId,
          history: history,
        );
        await _pendingSyncDao.deleteById(operation.id);
        historyOps++;
      } catch (error) {
        failedItems++;
        debugPrint(
          '[IkeepHouseholdDelta] queued history replay failed '
          'household=$householdId history=${operation.entityUuid} error=$error',
        );
      }
    }

    return _HouseholdDeltaPushOutcome(
      success: failedItems == 0,
      syncedItems: syncedItems,
      deletedItems: deletedItems,
      historyOps: historyOps,
      skippedItems: skippedItems,
      failedItems: failedItems,
      itemOutcomes: itemOutcomes,
      shouldClearCheckpoint: false,
    );
  }

  Future<bool> _applyRemoteSharedItemData({
    required String householdId,
    required String itemUuid,
    required Map<String, dynamic> data,
  }) async {
    final remoteItem = _sharedItemDocToLocalItem(
      householdId: householdId,
      itemId: itemUuid,
      data: data,
    );
    final localItem = await _itemDao.getItemByUuid(itemUuid);

    if (localItem == null) {
      await _itemDao.insertItem(remoteItem);
      await _itemCloudMediaService.replaceForItemFromCloudData(
        itemUuid: itemUuid,
        data: data,
      );
      await _restoreItemHistory(
        householdId: householdId,
        itemUuid: itemUuid,
      );
      _notifyLocalChange();
      return true;
    }

    final localImageReferences =
        await _itemCloudMediaService.getImageReferencesForItem(localItem.uuid);
    final localInvoiceReference =
        await _itemCloudMediaService.getInvoiceReferenceForItem(localItem.uuid);
    final mergeOutcome = _mergeRemoteSharedItemDelta(
      localItem: localItem,
      remoteItem: remoteItem,
      remoteData: data,
      localImageReferences: localImageReferences,
      localInvoiceReference: localInvoiceReference,
    );

    await _itemDao.updateItem(mergeOutcome.mergedItem);
    if (mergeOutcome.replaceSidecarFromRemote) {
      await _itemCloudMediaService.replaceForItemFromCloudData(
        itemUuid: itemUuid,
        data: data,
      );
    }
    if (mergeOutcome.restoreHistoryFromRemote) {
      await _restoreItemHistory(
        householdId: householdId,
        itemUuid: itemUuid,
      );
    }
    if (mergeOutcome.didChange) {
      _notifyLocalChange();
    }
    return mergeOutcome.didChange;
  }

  _HouseholdMergeOutcome _mergeRemoteSharedItemDelta({
    required Item localItem,
    required Item remoteItem,
    required Map<String, dynamic> remoteData,
    required List<ItemCloudMediaReference> localImageReferences,
    required ItemCloudMediaReference? localInvoiceReference,
  }) {
    final remoteOwnerUid = _ownerUidFromCloudData(remoteData) ??
        remoteItem.cloudId?.trim() ??
        localItem.cloudId?.trim();
    final currentUserOwnsItem = _isOwnedByCurrentUser(
      localItem,
      ownerUid: remoteOwnerUid,
    );

    final localContentAt = _contentTimestamp(localItem);
    final remoteContentAt = _remoteContentTimestamp(remoteData, remoteItem);
    final localLocationAt = localItem.lastMovedAt;
    final remoteLocationAt = remoteItem.lastMovedAt;
    final remoteMediaAt = _remoteMediaTimestamp(remoteData) ?? remoteContentAt;
    final localMediaDirty = _localImageMediaDirty(
          imagePaths: localItem.imagePaths,
          existingReferences: localImageReferences,
        ) ||
        _localInvoiceMediaDirty(
          invoicePath: localItem.invoicePath,
          existingReference: localInvoiceReference,
        );

    final remoteContentChanged = _remoteChangedSinceLastSync(
      remoteChangeAt: remoteContentAt,
      lastSyncedAt: localItem.lastSyncedAt,
    );
    final remoteLocationChanged = _remoteChangedSinceLastSync(
      remoteChangeAt: remoteLocationAt,
      lastSyncedAt: localItem.lastSyncedAt,
    );
    final remoteMediaChanged = _remoteChangedSinceLastSync(
      remoteChangeAt: remoteMediaAt,
      lastSyncedAt: localItem.lastSyncedAt,
    );
    final memberUnauthorizedContentDrift = !currentUserOwnsItem &&
        _memberHasUnauthorizedContentDrift(
          localItem: localItem,
          remoteItem: remoteItem,
        );
    final memberUnauthorizedMediaDrift =
        !currentUserOwnsItem && localMediaDirty;

    final localWinsContent = currentUserOwnsItem &&
        _isLocalNewer(
          localChangeAt: localContentAt,
          remoteChangeAt: remoteContentAt,
        );
    final localWinsLocation = _isLocalNewer(
      localChangeAt: localLocationAt,
      remoteChangeAt: remoteLocationAt,
    );
    final localWinsMedia = currentUserOwnsItem && localMediaDirty;

    final useRemoteContent = currentUserOwnsItem
        ? (remoteContentChanged && !localWinsContent)
        : (remoteContentChanged || memberUnauthorizedContentDrift);
    final useRemoteLocation = remoteLocationChanged && !localWinsLocation;
    final useRemoteMedia = currentUserOwnsItem
        ? (remoteMediaChanged && !localWinsMedia)
        : (remoteMediaChanged || memberUnauthorizedMediaDrift);

    var mergedItem = localItem.copyWith(
      cloudId: remoteOwnerUid ?? localItem.cloudId ?? localItem.uuid,
      householdId: remoteItem.householdId ?? localItem.householdId,
      visibility: ItemVisibility.household,
      updatedAt: _maxDateTime(
        localItem.updatedAt ?? localItem.savedAt,
        remoteItem.updatedAt ?? remoteItem.savedAt,
      ),
    );

    if (useRemoteContent) {
      mergedItem = _applyRemoteContentFields(
        localItem: mergedItem,
        remoteItem: remoteItem,
      );
    }
    if (useRemoteLocation) {
      mergedItem = _applyRemoteLocationFields(
        localItem: mergedItem,
        remoteItem: remoteItem,
      );
    }
    if (useRemoteMedia) {
      mergedItem = _applyRemoteMediaFields(
        localItem: mergedItem,
        remoteItem: remoteItem,
      );
    }

    final requiresPush = localWinsLocation ||
        (currentUserOwnsItem && (localWinsContent || localWinsMedia));
    mergedItem = mergedItem.copyWith(
      lastSyncedAt: requiresPush ? localItem.lastSyncedAt : DateTime.now(),
    );

    debugPrint(
      '[IkeepHouseholdDelta] conflict '
      'item=${localItem.uuid} owner=${currentUserOwnsItem ? "current" : "remote"} '
      'content=${useRemoteContent ? "remote" : localWinsContent ? "local" : "same"} '
      'location=${useRemoteLocation ? "remote" : localWinsLocation ? "local" : "same"} '
      'media=${useRemoteMedia ? "remote" : localWinsMedia ? "local" : "same"} '
      'memberBoundaryContent=$memberUnauthorizedContentDrift '
      'memberBoundaryMedia=$memberUnauthorizedMediaDrift',
    );

    return _HouseholdMergeOutcome(
      mergedItem: mergedItem,
      replaceSidecarFromRemote: useRemoteMedia,
      restoreHistoryFromRemote: useRemoteLocation,
      didChange: useRemoteContent || useRemoteLocation || useRemoteMedia,
    );
  }

  Future<_HouseholdTombstoneApplyOutcome> _applyRemoteSharedTombstone({
    required _HouseholdRemoteTombstone tombstone,
    required String source,
  }) async {
    final localItem = await _itemDao.getItemByUuid(tombstone.itemUuid);
    if (localItem == null) {
      await _clearQueuedSharedItemSync(tombstone.itemUuid);
      await _clearQueuedSharedHistoryForItem(tombstone.itemUuid);
      debugPrint(
        '[IkeepHouseholdDelta] tombstone with no local row '
        'item=${tombstone.itemUuid} reason=${tombstone.reason} source=$source',
      );
      return const _HouseholdTombstoneApplyOutcome();
    }

    final currentUserOwnsItem = _isOwnedByCurrentUser(
      localItem,
      ownerUid: tombstone.ownerUid,
    );
    final shouldApply = await _shouldApplyRemoteSharedTombstone(
      localItem: localItem,
      tombstone: tombstone,
      currentUserOwnsItem: currentUserOwnsItem,
    );
    if (!shouldApply) {
      debugPrint(
        '[IkeepHouseholdDelta] tombstone local-wins '
        'item=${tombstone.itemUuid} reason=${tombstone.reason} source=$source',
      );
      return const _HouseholdTombstoneApplyOutcome(localWins: true);
    }

    if (tombstone.reason == _deleteReasonOwnerUnshared && currentUserOwnsItem) {
      await _itemDao.updateItem(
        localItem.copyWith(
          visibility: ItemVisibility.private_,
          clearHouseholdId: true,
          sharedWithMemberUuids: const [],
          updatedAt: DateTime.now(),
          lastUpdatedAt: DateTime.now(),
        ),
      );
      await _clearQueuedSharedItemSync(localItem.uuid);
      await _clearQueuedSharedHistoryForItem(localItem.uuid);
      _notifyLocalChange();
      debugPrint(
        '[IkeepHouseholdDelta] tombstone converted owner item to private '
        'item=${localItem.uuid} source=$source',
      );
      return const _HouseholdTombstoneApplyOutcome(convertedToPrivate: true);
    }

    await _historyDao.deleteHistoryForItem(localItem.uuid);
    await _itemCloudMediaService.deleteForItem(localItem.uuid);
    await _itemDao.deleteItem(localItem.uuid);
    await _clearQueuedSharedItemSync(localItem.uuid);
    await _clearQueuedSharedHistoryForItem(localItem.uuid);
    _notifyLocalChange();
    debugPrint(
      '[IkeepHouseholdDelta] tombstone deleted local shared item '
      'item=${localItem.uuid} reason=${tombstone.reason} source=$source',
    );
    return const _HouseholdTombstoneApplyOutcome(deletedLocally: true);
  }

  Future<bool> _removeMissingRemoteSharedItem(Item localItem) async {
    if (_isOwnedByCurrentUser(localItem)) {
      await _itemDao.updateItem(
        localItem.copyWith(
          visibility: ItemVisibility.private_,
          clearHouseholdId: true,
          sharedWithMemberUuids: const [],
          updatedAt: DateTime.now(),
          lastUpdatedAt: DateTime.now(),
        ),
      );
      await _clearQueuedSharedItemSync(localItem.uuid);
      await _clearQueuedSharedHistoryForItem(localItem.uuid);
      _notifyLocalChange();
      return true;
    }

    await _historyDao.deleteHistoryForItem(localItem.uuid);
    await _itemCloudMediaService.deleteForItem(localItem.uuid);
    await _itemDao.deleteItem(localItem.uuid);
    await _clearQueuedSharedItemSync(localItem.uuid);
    await _clearQueuedSharedHistoryForItem(localItem.uuid);
    _notifyLocalChange();
    return false;
  }

  Future<void> _handleMembershipLoss({
    required String householdId,
    required String reason,
  }) async {
    final localSharedItems =
        await _itemDao.getSharedItems(householdId: householdId);
    if (localSharedItems.isEmpty) {
      return;
    }

    debugPrint(
      '[IkeepHouseholdDelta] applying membership loss '
      'household=$householdId items=${localSharedItems.length} reason=$reason',
    );

    for (final localItem in localSharedItems) {
      if (_isOwnedByCurrentUser(localItem)) {
        await _itemDao.updateItem(
          localItem.copyWith(
            visibility: ItemVisibility.private_,
            clearHouseholdId: true,
            sharedWithMemberUuids: const [],
            updatedAt: DateTime.now(),
            lastUpdatedAt: DateTime.now(),
          ),
        );
      } else {
        await _historyDao.deleteHistoryForItem(localItem.uuid);
        await _itemCloudMediaService.deleteForItem(localItem.uuid);
        await _itemDao.deleteItem(localItem.uuid);
      }
      await _clearQueuedSharedItemSync(localItem.uuid);
      await _clearQueuedSharedHistoryForItem(localItem.uuid);
    }

    _notifyLocalChange();
  }

  Future<void> _restoreItemHistory({
    required String householdId,
    required String itemUuid,
  }) async {
    try {
      final histories = await _householdCloudService.fetchItemHistory(
        householdId: householdId,
        itemUuid: itemUuid,
      );
      for (final history in histories) {
        await _historyDao.upsertHistory(history);
      }
    } catch (error) {
      debugPrint(
        '[IkeepHouseholdDelta] remote history restore failed '
        'household=$householdId item=$itemUuid error=$error',
      );
    }
  }

  Future<bool> _shouldApplyRemoteSharedTombstone({
    required Item localItem,
    required _HouseholdRemoteTombstone tombstone,
    required bool currentUserOwnsItem,
  }) async {
    if (!currentUserOwnsItem) {
      return true;
    }

    final lastSyncedAt = localItem.lastSyncedAt;
    if (lastSyncedAt == null) {
      return false;
    }
    if (!tombstone.changedAt.isAfter(lastSyncedAt)) {
      return false;
    }
    return !_localSharedItemNeedsPush(localItem);
  }

  String? _fallbackReasonForCheckpoint({
    required SyncCheckpointState? checkpoint,
    required HouseholdAccessState accessState,
  }) {
    if (accessState.accessUncertain) {
      return 'uncertain_membership_or_permissions';
    }
    if (checkpoint == null) {
      return 'missing_checkpoint';
    }

    final remoteCursor = checkpoint.lastKnownRemoteCheckpoint?.trim() ?? '';
    if (remoteCursor.isEmpty) {
      return 'missing_remote_checkpoint';
    }
    if (DateTime.tryParse(remoteCursor) == null) {
      return 'invalid_remote_checkpoint';
    }

    final lastFullSyncAt = checkpoint.lastFullSyncAt;
    if (lastFullSyncAt == null) {
      return 'missing_full_sync_anchor';
    }

    final now = DateTime.now().toUtc();
    if (lastFullSyncAt.isAfter(now.add(const Duration(minutes: 5)))) {
      return 'future_full_sync_anchor';
    }
    if (now.difference(lastFullSyncAt) > _deltaCheckpointMaxAge) {
      return 'stale_full_sync_anchor';
    }
    return null;
  }

  Future<SyncCheckpointState?> _loadCheckpoint(String householdId) async {
    final checkpoint = await _syncCheckpointDao.getByScope(
      _scopeForHousehold(householdId),
    );
    debugPrint(
      '[IkeepHouseholdDelta] checkpoint load '
      'household=$householdId found=${checkpoint != null}',
    );
    return checkpoint;
  }

  Future<void> _saveCheckpoint(SyncCheckpointState checkpoint) async {
    await _syncCheckpointDao.upsert(checkpoint);
    debugPrint(
      '[IkeepHouseholdDelta] checkpoint save '
      'scope=${checkpoint.syncScope} household=${checkpoint.householdId} '
      'pull=${checkpoint.lastSuccessfulPullAt?.toIso8601String()} '
      'push=${checkpoint.lastSuccessfulPushAt?.toIso8601String()} '
      'full=${checkpoint.lastFullSyncAt?.toIso8601String()} '
      'remote=${checkpoint.lastKnownRemoteCheckpoint}',
    );
  }

  Future<void> _clearCheckpoint(String householdId) {
    return _syncCheckpointDao.deleteByScope(_scopeForHousehold(householdId));
  }

  Future<void> _cleanupSharedTombstonesIfSafe({
    required String householdId,
    required SyncCheckpointState checkpoint,
  }) async {
    final remoteCursor = checkpoint.lastKnownRemoteCheckpoint?.trim();
    final lastFullSyncAt = checkpoint.lastFullSyncAt;
    final now = DateTime.now().toUtc();
    if (lastFullSyncAt == null ||
        now.difference(lastFullSyncAt) > _deltaCheckpointMaxAge ||
        remoteCursor == null ||
        remoteCursor.isEmpty ||
        DateTime.tryParse(remoteCursor) == null) {
      debugPrint(
        '[IkeepHouseholdDelta] tombstone cleanup skipped '
        'household=$householdId reason=unsafe_checkpoint_state',
      );
      return;
    }

    final cleanupCutoff = now.subtract(_sharedTombstoneRetention);
    try {
      await _householdCloudService.cleanupExpiredSharedTombstones(
        householdId: householdId,
        cutoffUtc: cleanupCutoff,
      );
    } catch (error) {
      debugPrint(
        '[IkeepHouseholdDelta] tombstone cleanup failed '
        'household=$householdId cutoff=${cleanupCutoff.toIso8601String()} '
        'error=$error',
      );
    }
  }

  Future<int> _dropQueuedSharedOpsForHousehold({
    required String householdId,
    required String reason,
  }) async {
    var droppedCount = 0;
    final queuedItemOps =
        await _pendingSyncDao.getByEntityType(_sharedItemEntityType);
    for (final operation in queuedItemOps) {
      final operationHouseholdId =
          (operation.payload['householdId'] as String?)?.trim();
      if (operationHouseholdId != householdId) {
        continue;
      }
      await _pendingSyncDao.deleteById(operation.id);
      droppedCount++;
      debugPrint(
        '[IkeepHouseholdDelta] dropped queued shared item op '
        'household=$householdId item=${operation.entityUuid} reason=$reason',
      );
    }

    final queuedHistoryOps =
        await _pendingSyncDao.getByEntityType(_sharedHistoryEntityType);
    for (final operation in queuedHistoryOps) {
      final operationHouseholdId =
          (operation.payload['householdId'] as String?)?.trim();
      if (operationHouseholdId != householdId) {
        continue;
      }
      await _pendingSyncDao.deleteById(operation.id);
      droppedCount++;
      debugPrint(
        '[IkeepHouseholdDelta] dropped queued shared history op '
        'household=$householdId history=${operation.entityUuid} reason=$reason',
      );
    }

    return droppedCount;
  }

  Future<void> _queueSharedItemUpsert({
    required Item item,
    required String householdId,
    required String reason,
  }) {
    return _pendingSyncDao.enqueue(
      operationType: 'upsert',
      entityType: _sharedItemEntityType,
      entityUuid: item.uuid,
      payload: {
        'householdId': householdId,
        'itemUuid': item.uuid,
        'itemName': item.name,
        'reason': reason,
        'item': item.toJson(),
      },
    );
  }

  Future<void> _queueSharedItemDelete({
    required String householdId,
    required String itemUuid,
    required String itemName,
    required String reason,
  }) {
    return _pendingSyncDao.enqueue(
      operationType: 'delete',
      entityType: _sharedItemEntityType,
      entityUuid: itemUuid,
      payload: {
        'householdId': householdId,
        'itemUuid': itemUuid,
        'itemName': itemName,
        'reason': reason,
      },
    );
  }

  Future<void> _queueSharedHistoryUpsert({
    required ItemLocationHistory history,
    required String householdId,
    required String reason,
  }) {
    return _pendingSyncDao.enqueue(
      operationType: 'upsert',
      entityType: _sharedHistoryEntityType,
      entityUuid: history.uuid,
      payload: {
        'householdId': householdId,
        'reason': reason,
        'history': history.toJson(),
      },
    );
  }

  Future<void> _clearQueuedSharedItemSync(String itemUuid) {
    return _pendingSyncDao.deleteByEntity(
      entityType: _sharedItemEntityType,
      entityUuid: itemUuid,
    );
  }

  Future<void> _clearQueuedSharedHistoryForItem(String itemUuid) async {
    final queuedHistoryOps =
        await _pendingSyncDao.getByEntityType(_sharedHistoryEntityType);
    for (final operation in queuedHistoryOps) {
      final historyPayload = operation.payload['history'];
      if (historyPayload is! Map) {
        continue;
      }
      final rawItemId = historyPayload['itemId'] ?? historyPayload['itemUuid'];
      if (rawItemId == itemUuid) {
        await _pendingSyncDao.deleteById(operation.id);
      }
    }
  }

  Future<SyncResult> _syncItemDeletion({
    required String itemUuid,
    String? householdId,
    required String reason,
  }) async {
    final resolvedHouseholdId = householdId ?? _activeHouseholdId;
    if (resolvedHouseholdId == null || resolvedHouseholdId.isEmpty) {
      return const SyncResult.idle();
    }

    try {
      await _householdCloudService.removeSharedItem(
        householdId: resolvedHouseholdId,
        itemUuid: itemUuid,
        reason: reason,
      );
      await _clearQueuedSharedHistoryForItem(itemUuid);
      await _clearQueuedSharedItemSync(itemUuid);
      return SyncResult.success();
    } catch (error) {
      await _queueSharedItemDelete(
        householdId: resolvedHouseholdId,
        itemUuid: itemUuid,
        itemName: itemUuid,
        reason: reason,
      );
      return SyncResult.error('Queued shared item delete: $error');
    }
  }

  String _scopeForHousehold(String householdId) {
    return '$_sharedScopePrefix:$householdId';
  }

  _HouseholdReplayDecision _sharedDeleteReplayDecision({
    required _HouseholdDeleteRequest request,
    required Item? localItem,
    required HouseholdSharedItemRemoteState remoteState,
  }) {
    final tombstone = _remoteTombstoneFromReplayState(remoteState);
    if (tombstone != null) {
      return _HouseholdReplayDecision.drop(
        reason: 'shared_tombstone_present:${tombstone.reason}',
        applyRemoteTombstone: tombstone,
      );
    }
    if (!remoteState.hasItem) {
      return const _HouseholdReplayDecision.drop(
        reason: 'shared_item_missing_remote',
      );
    }

    final resolvedOwnerUid = remoteState.ownerUid?.trim();
    if (localItem == null &&
        (resolvedOwnerUid == null || resolvedOwnerUid.isEmpty)) {
      return const _HouseholdReplayDecision.drop(
        reason: 'delete_owner_unknown',
      );
    }
    final isOwner = _isOwnedByCurrentUser(
      localItem ??
          Item(
            uuid: request.itemUuid,
            name: request.itemName,
            savedAt: DateTime.now(),
          ),
      ownerUid: resolvedOwnerUid,
    );
    if (!isOwner) {
      return const _HouseholdReplayDecision.drop(
        reason: 'delete_requires_owner_permission',
      );
    }

    return const _HouseholdReplayDecision.proceed();
  }

  _HouseholdReplayDecision _sharedItemUpsertReplayDecision({
    required Item item,
    required HouseholdSharedItemRemoteState remoteState,
  }) {
    final tombstone = _remoteTombstoneFromReplayState(remoteState);
    if (tombstone != null) {
      return _HouseholdReplayDecision.drop(
        reason: 'shared_tombstone_present:${tombstone.reason}',
        applyRemoteTombstone: tombstone,
      );
    }

    final currentUserOwnsItem = _isOwnedByCurrentUser(
      item,
      ownerUid: remoteState.ownerUid,
    );
    if (!currentUserOwnsItem && !remoteState.hasItem) {
      return const _HouseholdReplayDecision.drop(
        reason: 'member_cannot_recreate_missing_shared_doc',
      );
    }

    if (!currentUserOwnsItem) {
      return const _HouseholdReplayDecision.proceed(memberLocationOnly: true);
    }

    return const _HouseholdReplayDecision.proceed();
  }

  _HouseholdReplayDecision _sharedHistoryReplayDecision({
    required ItemLocationHistory history,
    required Item? localItem,
    required HouseholdSharedItemRemoteState remoteState,
  }) {
    if (history.itemUuid.trim().isEmpty) {
      return const _HouseholdReplayDecision.drop(
        reason: 'history_missing_item_uuid',
      );
    }
    final tombstone = _remoteTombstoneFromReplayState(remoteState);
    if (tombstone != null) {
      return _HouseholdReplayDecision.drop(
        reason: 'shared_tombstone_present:${tombstone.reason}',
        applyRemoteTombstone: tombstone,
      );
    }
    if (!remoteState.hasItem) {
      return const _HouseholdReplayDecision.drop(
        reason: 'shared_item_missing_for_history',
      );
    }
    if (localItem == null || !localItem.visibility.isHousehold) {
      return const _HouseholdReplayDecision.drop(
        reason: 'local_shared_item_missing_for_history',
      );
    }

    return const _HouseholdReplayDecision.proceed(memberLocationOnly: true);
  }

  _HouseholdRemoteTombstone? _remoteTombstoneFromReplayState(
    HouseholdSharedItemRemoteState remoteState,
  ) {
    final tombstoneData = remoteState.tombstoneData;
    if (tombstoneData == null) {
      return null;
    }
    return _remoteSharedTombstoneFromData(remoteState.itemUuid, tombstoneData);
  }

  String? _historyItemUuidFromOperation(PendingSyncOperation operation) {
    final historyPayload = operation.payload['history'];
    if (historyPayload is! Map) {
      return null;
    }
    return (historyPayload['itemId'] as String? ??
            historyPayload['itemUuid'] as String?)
        ?.trim();
  }

  String? _ownerUidFromCloudData(Map<String, dynamic> data) {
    return (data['ownerUid'] as String?)?.trim();
  }

  bool _isOwnedByCurrentUser(Item item, {String? ownerUid}) {
    final currentUserUid = _auth.currentUser?.uid.trim();
    if (currentUserUid == null || currentUserUid.isEmpty) {
      return true;
    }
    final resolvedOwnerUid = (ownerUid ?? item.cloudId)?.trim();
    if (resolvedOwnerUid == null || resolvedOwnerUid.isEmpty) {
      return true;
    }
    return resolvedOwnerUid == currentUserUid;
  }

  bool _localSharedItemNeedsPush(Item item) {
    final lastSyncedAt = item.lastSyncedAt;
    if (lastSyncedAt == null) {
      return true;
    }
    final updatedAt = item.updatedAt ?? item.savedAt;
    if (updatedAt.isAfter(lastSyncedAt)) {
      return true;
    }
    final movedAt = item.lastMovedAt;
    if (movedAt != null && movedAt.isAfter(lastSyncedAt)) {
      return true;
    }
    return false;
  }

  bool _localImageMediaDirty({
    required List<String> imagePaths,
    required List<ItemCloudMediaReference> existingReferences,
  }) {
    if (imagePaths.isEmpty) {
      return existingReferences.isNotEmpty;
    }
    if (imagePaths.length != existingReferences.length) {
      return true;
    }

    final sortedReferences = [...existingReferences]
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    for (var index = 0; index < imagePaths.length; index++) {
      final path = imagePaths[index].trim();
      final reference = sortedReferences[index];
      if (path.isEmpty) {
        return true;
      }
      if (path == reference.storagePath) {
        continue;
      }
      if (reference.thumbnailPath?.trim().isNotEmpty == true &&
          path == reference.thumbnailPath!.trim()) {
        continue;
      }
      if (!path.startsWith('http://') &&
          !path.startsWith('https://') &&
          !path.startsWith('gs://') &&
          !path.startsWith('users/')) {
        return true;
      }
    }
    return false;
  }

  bool _localInvoiceMediaDirty({
    required String? invoicePath,
    required ItemCloudMediaReference? existingReference,
  }) {
    final trimmedInvoicePath = invoicePath?.trim();
    if (trimmedInvoicePath == null || trimmedInvoicePath.isEmpty) {
      return existingReference != null;
    }
    if (existingReference == null) {
      return true;
    }
    if (trimmedInvoicePath == existingReference.storagePath) {
      return false;
    }
    if (!trimmedInvoicePath.startsWith('http://') &&
        !trimmedInvoicePath.startsWith('https://') &&
        !trimmedInvoicePath.startsWith('gs://') &&
        !trimmedInvoicePath.startsWith('users/')) {
      return true;
    }
    return false;
  }

  Item _sanitizeMemberReplayItem({
    required Item localItem,
    required Item remoteItem,
  }) {
    var sanitizedItem = localItem.copyWith(
      cloudId: remoteItem.cloudId ?? localItem.cloudId,
      householdId: remoteItem.householdId ?? localItem.householdId,
      visibility: ItemVisibility.household,
      sharedWithMemberUuids: remoteItem.sharedWithMemberUuids,
    );
    sanitizedItem = _applyRemoteContentFields(
      localItem: sanitizedItem,
      remoteItem: remoteItem,
    );
    sanitizedItem = _applyRemoteMediaFields(
      localItem: sanitizedItem,
      remoteItem: remoteItem,
    );

    // Members may keep their local location move and history intent, but not
    // owner-authoritative content, media, or share-state fields.
    return sanitizedItem.copyWith(
      locationUuid: localItem.locationUuid,
      areaUuid: localItem.areaUuid,
      roomUuid: localItem.roomUuid,
      zoneUuid: localItem.zoneUuid,
      latitude: localItem.latitude,
      longitude: localItem.longitude,
      lastMovedAt: localItem.lastMovedAt,
      updatedAt: localItem.updatedAt,
      lastSyncedAt: localItem.lastSyncedAt,
      locationName: localItem.locationName,
      locationFullPath: localItem.locationFullPath,
    );
  }

  bool _memberHasUnauthorizedContentDrift({
    required Item localItem,
    required Item remoteItem,
  }) {
    return localItem.name != remoteItem.name ||
        !_stringListsEqual(localItem.tags, remoteItem.tags) ||
        !_stringListsEqual(
          localItem.sharedWithMemberUuids,
          remoteItem.sharedWithMemberUuids,
        ) ||
        localItem.isArchived != remoteItem.isArchived ||
        (localItem.notes ?? '') != (remoteItem.notes ?? '') ||
        localItem.isLent != remoteItem.isLent ||
        (localItem.lentTo ?? '') != (remoteItem.lentTo ?? '') ||
        !_sameDateTime(localItem.lentOn, remoteItem.lentOn) ||
        !_sameDateTime(
          localItem.expectedReturnDate,
          remoteItem.expectedReturnDate,
        ) ||
        !_sameDateTime(localItem.expiryDate, remoteItem.expiryDate) ||
        !_sameDateTime(
          localItem.warrantyEndDate,
          remoteItem.warrantyEndDate,
        ) ||
        localItem.seasonCategory != remoteItem.seasonCategory ||
        localItem.lentReminderAfterDays != remoteItem.lentReminderAfterDays ||
        localItem.isAvailableForLending != remoteItem.isAvailableForLending ||
        localItem.visibility != remoteItem.visibility ||
        (localItem.householdId ?? '') != (remoteItem.householdId ?? '');
  }

  bool _stringListsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index].trim() != b[index].trim()) {
        return false;
      }
    }
    return true;
  }

  bool _sameDateTime(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    return a.toUtc().millisecondsSinceEpoch == b.toUtc().millisecondsSinceEpoch;
  }

  Item _sharedItemDocToLocalItem({
    required String householdId,
    required String itemId,
    required Map<String, dynamic> data,
  }) {
    final restoredImagePaths =
        _itemCloudMediaService.restoredImagePathsFromCloudData(data);
    final restoredInvoicePath =
        _itemCloudMediaService.restoredInvoicePathFromCloudData(data);

    return Item(
      uuid: itemId,
      name: data['name'] as String? ?? 'Shared item',
      locationUuid: data['locationUuid'] as String?,
      areaUuid: data['areaUuid'] as String?,
      roomUuid: data['roomUuid'] as String?,
      zoneUuid: data['zoneUuid'] as String?,
      imagePaths: restoredImagePaths,
      tags: List<String>.from(data['tags'] as List? ?? const []),
      savedAt: _parseDateTime(data['savedAt']) ??
          _parseDateTime(data['createdAt']) ??
          DateTime.now(),
      updatedAt: _householdCloudService.resolveSharedItemChangedAt(data),
      lastUpdatedAt: _parseDateTime(data['lastUpdatedAt']) ??
          _parseDateTime(data['lastContentUpdatedAt']) ??
          _parseDateTime(data['updatedAt']),
      lastMovedAt: _parseDateTime(data['lastMovedAt']),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      expiryDate: _parseDateTime(data['expiryDate']),
      warrantyEndDate: _parseDateTime(data['warrantyEndDate']),
      isArchived: data['isArchived'] as bool? ?? false,
      notes: data['notes'] as String? ?? data['note'] as String?,
      invoicePath: restoredInvoicePath,
      invoiceFileName: data['invoiceFileName'] as String?,
      invoiceFileSizeBytes:
          (data['invoiceUploadedFileSizeBytes'] as num?)?.toInt() ??
              (data['invoiceFileSizeBytes'] as num?)?.toInt(),
      cloudId: data['ownerUid'] as String?,
      lastSyncedAt: _householdCloudService.resolveSharedItemChangedAt(data),
      isBackedUp: true,
      isLent: data['isLent'] as bool? ?? false,
      lentTo: data['lentToName'] as String? ?? data['lentTo'] as String?,
      lentOn: _parseDateTime(data['lentOn']),
      expectedReturnDate: _parseDateTime(data['expectedReturnDate']),
      seasonCategory: (data['seasonCategory'] as String?) ?? 'all_year',
      lentReminderAfterDays: (data['lentReminderAfterDays'] as num?)?.toInt(),
      isAvailableForLending: (data['isAvailableForLending'] as bool?) ?? true,
      visibility: ItemVisibility.household,
      householdId: householdId,
      sharedWithMemberUuids: List<String>.from(
        (data['sharedWithMemberUuids'] as List?) ?? const [],
      ),
      locationName: data['locationName'] as String?,
    );
  }

  DateTime _contentTimestamp(Item item) {
    return item.lastUpdatedAt ?? item.updatedAt ?? item.savedAt;
  }

  DateTime? _remoteContentTimestamp(
    Map<String, dynamic> remoteData,
    Item remoteItem,
  ) {
    return _parseDateTime(remoteData['lastContentUpdatedAt']) ??
        remoteItem.lastUpdatedAt ??
        remoteItem.updatedAt ??
        remoteItem.savedAt;
  }

  DateTime? _remoteMediaTimestamp(Map<String, dynamic> remoteData) {
    final timestamps = <DateTime>[];
    final imageMedia = remoteData['imageMedia'];
    if (imageMedia is List) {
      for (final entry in imageMedia) {
        if (entry is! Map) continue;
        final updatedAt = _parseDateTime(entry['updatedAt']);
        if (updatedAt != null) {
          timestamps.add(updatedAt);
        }
      }
    }
    final invoiceMedia = remoteData['invoiceMedia'];
    if (invoiceMedia is Map) {
      final updatedAt = _parseDateTime(invoiceMedia['updatedAt']);
      if (updatedAt != null) {
        timestamps.add(updatedAt);
      }
    }
    if (timestamps.isEmpty) {
      return null;
    }
    timestamps.sort();
    return timestamps.last;
  }

  bool _remoteChangedSinceLastSync({
    required DateTime? remoteChangeAt,
    required DateTime? lastSyncedAt,
  }) {
    if (remoteChangeAt == null) {
      return false;
    }
    if (lastSyncedAt == null) {
      return true;
    }
    return remoteChangeAt.isAfter(lastSyncedAt);
  }

  bool _isLocalNewer({
    required DateTime? localChangeAt,
    required DateTime? remoteChangeAt,
  }) {
    if (localChangeAt == null) {
      return false;
    }
    if (remoteChangeAt == null) {
      return true;
    }
    return localChangeAt.isAfter(remoteChangeAt);
  }

  Item _applyRemoteContentFields({
    required Item localItem,
    required Item remoteItem,
  }) {
    return localItem.copyWith(
      name: remoteItem.name,
      tags: remoteItem.tags,
      savedAt: remoteItem.savedAt,
      updatedAt: remoteItem.updatedAt,
      lastUpdatedAt: remoteItem.lastUpdatedAt,
      expiryDate: remoteItem.expiryDate,
      clearExpiryDate: remoteItem.expiryDate == null,
      warrantyEndDate: remoteItem.warrantyEndDate,
      clearWarrantyEndDate: remoteItem.warrantyEndDate == null,
      isArchived: remoteItem.isArchived,
      notes: remoteItem.notes,
      clearNotes: remoteItem.notes == null,
      isLent: remoteItem.isLent,
      lentTo: remoteItem.lentTo,
      clearLentTo: remoteItem.lentTo == null,
      lentOn: remoteItem.lentOn,
      clearLentOn: remoteItem.lentOn == null,
      expectedReturnDate: remoteItem.expectedReturnDate,
      clearExpectedReturnDate: remoteItem.expectedReturnDate == null,
      seasonCategory: remoteItem.seasonCategory,
      lentReminderAfterDays: remoteItem.lentReminderAfterDays,
      clearLentReminderAfterDays: remoteItem.lentReminderAfterDays == null,
      isAvailableForLending: remoteItem.isAvailableForLending,
      visibility: remoteItem.visibility,
      householdId: remoteItem.householdId,
      clearHouseholdId: remoteItem.householdId == null,
      sharedWithMemberUuids: remoteItem.sharedWithMemberUuids,
    );
  }

  Item _applyRemoteLocationFields({
    required Item localItem,
    required Item remoteItem,
  }) {
    return localItem.copyWith(
      locationUuid: remoteItem.locationUuid,
      clearLocationUuid: remoteItem.locationUuid == null,
      areaUuid: remoteItem.areaUuid,
      clearAreaUuid: remoteItem.areaUuid == null,
      roomUuid: remoteItem.roomUuid,
      clearRoomUuid: remoteItem.roomUuid == null,
      zoneUuid: remoteItem.zoneUuid,
      clearZoneUuid: remoteItem.zoneUuid == null,
      latitude: remoteItem.latitude,
      longitude: remoteItem.longitude,
      lastMovedAt: remoteItem.lastMovedAt,
    );
  }

  Item _applyRemoteMediaFields({
    required Item localItem,
    required Item remoteItem,
  }) {
    return localItem.copyWith(
      imagePaths: remoteItem.imagePaths,
      invoicePath: remoteItem.invoicePath,
      clearInvoicePath: remoteItem.invoicePath == null,
      invoiceFileName: remoteItem.invoiceFileName,
      clearInvoiceFileName: remoteItem.invoiceFileName == null,
      invoiceFileSizeBytes: remoteItem.invoiceFileSizeBytes,
      clearInvoiceFileSizeBytes: remoteItem.invoiceFileSizeBytes == null,
    );
  }

  DateTime _maxDateTime(DateTime a, DateTime b) {
    return a.isAfter(b) ? a : b;
  }

  _HouseholdRemoteTombstone? _remoteSharedTombstoneFromData(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final itemUuid = ((data['itemUuid'] as String?) ?? documentId).trim();
    final changedAt = _householdCloudService.resolveSharedTombstoneChangedAt(
      data,
    );
    if (itemUuid.isEmpty || changedAt == null) {
      return null;
    }

    final reason = (data['reason'] as String?)?.trim();
    return _HouseholdRemoteTombstone(
      itemUuid: itemUuid,
      ownerUid: (data['ownerUid'] as String?)?.trim(),
      reason: reason?.isNotEmpty == true ? reason! : _deleteReasonOwnerDeleted,
      changedAt: changedAt,
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  void _notifyLocalChange() {
    if (!_localChangesController.isClosed) {
      _localChangesController.add(null);
    }
  }

  bool _shouldObserveSyncResult(SyncResult? result) {
    return result != null &&
        !result.isSyncing &&
        (result.isSuccess || result.hasError || result.isTimedOut);
  }

  Future<void> _observeSyncRun({
    required String source,
    required SyncResult result,
  }) async {
    try {
      await _cloudObservationService.recordSyncRun(
        source: source,
        result: result,
      );
    } catch (error) {
      debugPrint(
        '[IkeepObserve] household sync observation failed '
        'source=$source error=$error',
      );
    }
  }

  Future<void> dispose() async {
    await stopSync();
    await _localChangesController.close();
  }
}

class _HouseholdDeltaFallbackException implements Exception {
  const _HouseholdDeltaFallbackException(this.reason);

  final String reason;
}

class _HouseholdRemoteTombstone {
  const _HouseholdRemoteTombstone({
    required this.itemUuid,
    required this.reason,
    required this.changedAt,
    this.ownerUid,
  });

  final String itemUuid;
  final String reason;
  final DateTime changedAt;
  final String? ownerUid;
}

class _HouseholdRemoteDeltaEvent {
  const _HouseholdRemoteDeltaEvent.item({
    required this.itemUuid,
    required this.changedAt,
    required this.data,
  }) : tombstone = null;

  _HouseholdRemoteDeltaEvent.tombstone({
    required _HouseholdRemoteTombstone tombstone,
  })  : itemUuid = tombstone.itemUuid,
        changedAt = tombstone.changedAt,
        data = null,
        tombstone = tombstone;

  final String itemUuid;
  final DateTime changedAt;
  final Map<String, dynamic>? data;
  final _HouseholdRemoteTombstone? tombstone;
}

class _HouseholdDeltaPullOutcome {
  const _HouseholdDeltaPullOutcome({
    required this.success,
    required this.importedCount,
    required this.deletedCount,
    required this.unsharedCount,
    required this.membershipConvertedCount,
  });

  final bool success;
  final int importedCount;
  final int deletedCount;
  final int unsharedCount;
  final int membershipConvertedCount;
}

class _HouseholdDeltaPushOutcome {
  const _HouseholdDeltaPushOutcome({
    required this.success,
    required this.syncedItems,
    required this.deletedItems,
    required this.historyOps,
    required this.skippedItems,
    required this.failedItems,
    required this.itemOutcomes,
    required this.shouldClearCheckpoint,
  });

  final bool success;
  final int syncedItems;
  final int deletedItems;
  final int historyOps;
  final int skippedItems;
  final int failedItems;
  final List<ItemSyncOutcome> itemOutcomes;
  final bool shouldClearCheckpoint;
}

class _HouseholdTombstoneApplyOutcome {
  const _HouseholdTombstoneApplyOutcome({
    this.deletedLocally = false,
    this.convertedToPrivate = false,
    this.convertedMembershipLocally = false,
    this.localWins = false,
  });

  final bool deletedLocally;
  final bool convertedToPrivate;
  final bool convertedMembershipLocally;
  final bool localWins;
}

class _HouseholdMergeOutcome {
  const _HouseholdMergeOutcome({
    required this.mergedItem,
    required this.replaceSidecarFromRemote,
    required this.restoreHistoryFromRemote,
    required this.didChange,
  });

  final Item mergedItem;
  final bool replaceSidecarFromRemote;
  final bool restoreHistoryFromRemote;
  final bool didChange;
}

class _HouseholdReplayDecision {
  const _HouseholdReplayDecision.proceed({
    this.memberLocationOnly = false,
  })  : proceed = true,
        reason = 'proceed',
        applyRemoteTombstone = null;

  const _HouseholdReplayDecision.drop({
    required this.reason,
    this.applyRemoteTombstone,
  })  : proceed = false,
        memberLocationOnly = false;

  final bool proceed;
  final bool memberLocationOnly;
  final String reason;
  final _HouseholdRemoteTombstone? applyRemoteTombstone;
}

class _HouseholdDeleteRequest {
  const _HouseholdDeleteRequest({
    required this.itemUuid,
    required this.itemName,
    required this.reason,
    this.queueId,
  });

  final String itemUuid;
  final String itemName;
  final String reason;
  final int? queueId;
}
