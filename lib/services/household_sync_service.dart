import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/database/history_dao.dart';
import '../data/database/item_dao.dart';
import '../data/database/pending_sync_dao.dart';
import '../domain/models/item.dart';
import '../domain/models/item_location_history.dart';
import '../domain/models/item_visibility.dart';
import '../domain/models/sync_status.dart';
import 'household_cloud_service.dart';

class HouseholdSyncService {
  HouseholdSyncService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required ItemDao itemDao,
    required HistoryDao historyDao,
    required PendingSyncDao pendingSyncDao,
    required HouseholdCloudService householdCloudService,
  })  : _auth = auth,
        _firestore = firestore,
        _itemDao = itemDao,
        _historyDao = historyDao,
        _pendingSyncDao = pendingSyncDao,
        _householdCloudService = householdCloudService;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final ItemDao _itemDao;
  final HistoryDao _historyDao;
  final PendingSyncDao _pendingSyncDao;
  final HouseholdCloudService _householdCloudService;
  final StreamController<void> _localChangesController =
      StreamController<void>.broadcast();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sharedItemsSub;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _historySubscriptions = {};
  final Map<String, String?> _remoteOwnerByItemId = {};

  String? _activeHouseholdId;

  static const _householdsCol = 'households';
  static const _sharedItemsSubcol = 'shared_items';
  static const _historySubcol = 'history';

  bool get isRunning => _activeHouseholdId != null;
  Stream<void> get localChanges => _localChangesController.stream;

  Future<SyncResult> startSync(String householdId) async {
    if (householdId.isEmpty) {
      return const SyncResult.error('Household id is required');
    }

    await stopSync();
    _activeHouseholdId = householdId;

    try {
      _sharedItemsSub = _sharedItemsCollection(householdId)
          .snapshots(includeMetadataChanges: true)
          .listen(
        (snapshot) async {
          for (final change in snapshot.docChanges) {
            await _handleSharedItemChange(householdId, change);
          }
          // Firestore's local cache handles transient offline writes. The
          // SQLite-backed pending queue below covers app-level replay if a
          // write fails before Firestore can accept it.
          await flushPendingOperations();
        },
      );

      await flushPendingOperations();
      return SyncResult.success();
    } catch (e) {
      _activeHouseholdId = null;
      return SyncResult.error('Failed to start household sync: $e');
    }
  }

  Future<void> stopSync() async {
    await _sharedItemsSub?.cancel();
    _sharedItemsSub = null;

    for (final sub in _historySubscriptions.values) {
      await sub.cancel();
    }
    _historySubscriptions.clear();
    _remoteOwnerByItemId.clear();
    _activeHouseholdId = null;
  }

  Future<SyncResult> syncLocalItemChange(Item item) async {
    if (!item.visibility.isHousehold) {
      return _syncItemDeletion(
        itemUuid: item.uuid,
        householdId: item.householdId,
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
      return SyncResult.success();
    } catch (e) {
      await _pendingSyncDao.enqueue(
        operationType: 'upsert',
        entityType: 'item',
        entityUuid: item.uuid,
        payload: {
          'householdId': householdId,
          'item': item.copyWith(householdId: householdId).toJson(),
        },
      );
      return SyncResult.error('Queued shared item sync: $e');
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
      return SyncResult.success();
    } catch (e) {
      await _pendingSyncDao.enqueue(
        operationType: 'upsert',
        entityType: 'history',
        entityUuid: history.uuid,
        payload: {
          'householdId': householdId,
          'history': history.toJson(),
        },
      );
      return SyncResult.error('Queued shared history sync: $e');
    }
  }

  Future<SyncResult> syncLocalDeletion({
    required String itemUuid,
    String? householdId,
  }) async {
    return _syncItemDeletion(itemUuid: itemUuid, householdId: householdId);
  }

  Future<void> flushPendingOperations() async {
    final operations = await _pendingSyncDao.getAll();
    for (final operation in operations) {
      try {
        await _replay(operation);
        await _pendingSyncDao.deleteById(operation.id);
      } catch (_) {
        // Leave queued for the next sync cycle. Firestore offline persistence
        // handles transient network loss; this queue covers app-level retries.
      }
    }
  }

  CollectionReference<Map<String, dynamic>> _sharedItemsCollection(
    String householdId,
  ) {
    return _firestore
        .collection(_householdsCol)
        .doc(householdId)
        .collection(_sharedItemsSubcol);
  }

  Future<void> _handleSharedItemChange(
    String householdId,
    DocumentChange<Map<String, dynamic>> change,
  ) async {
    final doc = change.doc;
    final itemId = doc.id;

    if (change.type == DocumentChangeType.removed) {
      await _handleRemoteItemRemoved(householdId, itemId);
      return;
    }

    final data = doc.data();
    if (data == null) return;

    _remoteOwnerByItemId[itemId] = data['ownerUid'] as String?;
    final remoteItem = _sharedItemDocToLocalItem(
      householdId: householdId,
      itemId: itemId,
      data: data,
    );

    final localItem = await _itemDao.getItemByUuid(itemId);
    if (_isRemoteNewer(localItem, remoteItem)) {
      await _itemDao.insertItem(remoteItem);
      _notifyLocalChange();
    }

    await _ensureHistoryListener(householdId, itemId);
  }

  Future<void> _handleRemoteItemRemoved(
    String householdId,
    String itemId,
  ) async {
    final localItem = await _itemDao.getItemByUuid(itemId);
    final ownerUid = _remoteOwnerByItemId[itemId];
    _remoteOwnerByItemId.remove(itemId);

    final historySub = _historySubscriptions.remove(itemId);
    await historySub?.cancel();

    if (localItem == null) return;

    final isOwnedByCurrentUser =
        ownerUid != null && ownerUid == _auth.currentUser?.uid;
    if (isOwnedByCurrentUser) {
      await _itemDao.updateItem(
        localItem.copyWith(
          visibility: ItemVisibility.private_,
          householdId: null,
          updatedAt: DateTime.now(),
        ),
      );
      _notifyLocalChange();
      return;
    }

    await _historyDao.deleteHistoryForItem(itemId);
    await _itemDao.deleteItem(itemId);
    _notifyLocalChange();
  }

  Future<void> _ensureHistoryListener(String householdId, String itemId) async {
    if (_historySubscriptions.containsKey(itemId)) return;

    final sub = _sharedItemsCollection(householdId)
        .doc(itemId)
        .collection(_historySubcol)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        await _handleHistoryChange(householdId, itemId, change);
      }
    });

    _historySubscriptions[itemId] = sub;
  }

  Future<void> _handleHistoryChange(
    String householdId,
    String itemId,
    DocumentChange<Map<String, dynamic>> change,
  ) async {
    if (change.type == DocumentChangeType.removed) {
      return;
    }

    final data = change.doc.data();
    if (data == null) return;

    final remoteHistory = _historyDocToLocalHistory(
      householdId: householdId,
      itemId: itemId,
      historyId: change.doc.id,
      data: data,
    );

    final latestLocal = await _historyDao.getLatestHistoryForItem(itemId);
    final latestLocalTime = latestLocal?.movedAt;
    if (latestLocalTime == null ||
        !latestLocalTime.isAfter(remoteHistory.movedAt)) {
      await _historyDao.upsertHistory(remoteHistory);
      _notifyLocalChange();
    }
  }

  Item _sharedItemDocToLocalItem({
    required String householdId,
    required String itemId,
    required Map<String, dynamic> data,
  }) {
    return Item(
      uuid: itemId,
      name: data['name'] as String? ?? 'Shared item',
      locationUuid: data['locationUuid'] as String?,
      imagePaths: List<String>.from(data['imagePaths'] as List? ?? const []),
      tags: List<String>.from(data['tags'] as List? ?? const []),
      savedAt: _parseDateTime(data['savedAt']) ??
          _parseDateTime(data['createdAt']) ??
          DateTime.now(),
      updatedAt: _parseDateTime(data['updatedAt']),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      expiryDate: _parseDateTime(data['expiryDate']),
      isArchived: data['isArchived'] as bool? ?? false,
      notes: data['notes'] as String?,
      cloudId: data['ownerUid'] as String?,
      lastSyncedAt: _parseDateTime(data['updatedAt']),
      isLent: data['isLent'] as bool? ?? false,
      lentTo: data['lentTo'] as String? ?? data['lentToName'] as String?,
      lentOn: _parseDateTime(data['lentOn']),
      expectedReturnDate: _parseDateTime(data['expectedReturnDate']),
      lentReminderAfterDays: data['lentReminderAfterDays'] as int?,
      isAvailableForLending:
          (data['isAvailableForLending'] as bool?) ?? true,
      visibility: ItemVisibility.household,
      householdId: householdId,
      locationName: data['locationName'] as String?,
    );
  }

  ItemLocationHistory _historyDocToLocalHistory({
    required String householdId,
    required String itemId,
    required String historyId,
    required Map<String, dynamic> data,
  }) {
    return ItemLocationHistory(
      uuid: historyId,
      itemUuid: data['itemId'] as String? ?? itemId,
      locationUuid: data['locationUuid'] as String?,
      locationName: data['locationName'] as String? ?? 'Unknown',
      movedAt: _parseDateTime(data['timestamp']) ?? DateTime.now(),
      movedByMemberUuid: data['userId'] as String?,
      movedByName: data['userName'] as String?,
      userEmail: data['userEmail'] as String?,
      householdId: householdId,
      actionDescription: data['actionDescription'] as String?,
    );
  }

  bool _isRemoteNewer(Item? localItem, Item remoteItem) {
    if (localItem == null) return true;

    final localUpdatedAt = localItem.updatedAt ?? localItem.savedAt;
    final remoteUpdatedAt = remoteItem.updatedAt ?? remoteItem.savedAt;
    // Last-write-wins: whichever side has the newest resolved timestamp
    // becomes the SQLite version that drives the UI.
    return !localUpdatedAt.isAfter(remoteUpdatedAt);
  }

  Future<void> _replay(PendingSyncOperation operation) async {
    final householdId = operation.payload['householdId'] as String?;
    if (householdId == null || householdId.isEmpty) return;

    switch (operation.entityType) {
      case 'item':
        if (operation.operationType == 'delete') {
          await _householdCloudService.removeSharedItem(
            householdId: householdId,
            itemUuid: operation.entityUuid,
          );
          return;
        }

        final itemPayload = Map<String, dynamic>.from(
          operation.payload['item'] as Map,
        );
        await _householdCloudService.syncSharedItem(
          householdId: householdId,
          item: Item.fromJson(itemPayload),
        );
        return;
      case 'history':
        final historyPayload = Map<String, dynamic>.from(
          operation.payload['history'] as Map,
        );
        await _householdCloudService.syncItemHistory(
          householdId: householdId,
          history: ItemLocationHistory.fromJson(historyPayload),
        );
        return;
    }
  }

  Future<SyncResult> _syncItemDeletion({
    required String itemUuid,
    String? householdId,
  }) async {
    final resolvedHouseholdId = householdId ?? _activeHouseholdId;
    if (resolvedHouseholdId == null || resolvedHouseholdId.isEmpty) {
      return const SyncResult.idle();
    }

    try {
      await _householdCloudService.removeSharedItem(
        householdId: resolvedHouseholdId,
        itemUuid: itemUuid,
      );
      return SyncResult.success();
    } catch (e) {
      await _pendingSyncDao.enqueue(
        operationType: 'delete',
        entityType: 'item',
        entityUuid: itemUuid,
        payload: {'householdId': resolvedHouseholdId},
      );
      return SyncResult.error('Queued shared item delete: $e');
    }
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

  Future<void> dispose() async {
    await stopSync();
    await _localChangesController.close();
  }
}
