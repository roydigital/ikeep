import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/feature_limits.dart';
import '../core/errors/app_exception.dart';
import '../data/database/history_dao.dart';
import '../data/database/item_dao.dart';
import '../data/database/location_dao.dart';
import '../data/database/pending_sync_dao.dart';
import '../data/database/sync_checkpoint_dao.dart';
import '../domain/models/cloud_media_descriptor.dart';
import '../domain/models/item.dart';
import '../domain/models/item_cloud_media_reference.dart';
import '../domain/models/item_location_history.dart';
import '../domain/models/item_visibility.dart';
import '../domain/models/location_model.dart';
import '../domain/models/sync_checkpoint_state.dart';
import '../domain/models/sync_status.dart';
import 'firebase_image_upload_service.dart';
import 'firebase_invoice_storage_service.dart';
import 'cloud_observation_service.dart';
import 'cloud_quota_service.dart';
import 'item_cloud_media_service.dart';
import 'sync_service.dart';

@visibleForTesting
List<LocationModel> orderLocationsForLocalUpsert({
  required Iterable<LocationModel> locations,
  required Set<String> existingLocationUuids,
}) {
  final pendingByUuid = <String, LocationModel>{
    for (final location in locations) location.uuid: location,
  };
  final resolvedUuids = <String>{...existingLocationUuids};
  final ordered = <LocationModel>[];

  while (pendingByUuid.isNotEmpty) {
    final ready = pendingByUuid.values.where((location) {
      final parentUuid = location.parentUuid;
      return parentUuid == null || resolvedUuids.contains(parentUuid);
    }).toList()
      ..sort(_compareLocationRestoreOrder);

    if (ready.isNotEmpty) {
      for (final location in ready) {
        ordered.add(location);
        resolvedUuids.add(location.uuid);
        pendingByUuid.remove(location.uuid);
      }
      continue;
    }

    // If cloud data contains an orphaned or cyclic parent reference, restore
    // one location as a root to avoid hard-failing the entire sync.
    final fallback = pendingByUuid.values.toList()
      ..sort(_compareLocationRestoreOrder);
    final restoredAsRoot = fallback.first.copyWith(clearParentUuid: true);
    ordered.add(restoredAsRoot);
    resolvedUuids.add(restoredAsRoot.uuid);
    pendingByUuid.remove(restoredAsRoot.uuid);
  }

  return ordered;
}

int _compareLocationRestoreOrder(LocationModel a, LocationModel b) {
  final depthCompare =
      _locationRestoreDepth(a).compareTo(_locationRestoreDepth(b));
  if (depthCompare != 0) return depthCompare;

  final createdAtCompare = a.createdAt.compareTo(b.createdAt);
  if (createdAtCompare != 0) return createdAtCompare;

  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

int _locationRestoreDepth(LocationModel location) {
  final fullPath = location.fullPath?.trim();
  if (fullPath == null || fullPath.isEmpty) {
    return location.parentUuid == null ? 0 : 1;
  }

  return ' > '.allMatches(fullPath).length;
}

class FirebaseSyncService implements SyncService {
  FirebaseSyncService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required ItemDao itemDao,
    required LocationDao locationDao,
    required HistoryDao historyDao,
    required SyncCheckpointDao syncCheckpointDao,
    required PendingSyncDao pendingSyncDao,
    required FirebaseImageUploadService imageUploadService,
    required FirebaseInvoiceStorageService invoiceStorageService,
    required ItemCloudMediaService itemCloudMediaService,
    required CloudQuotaService cloudQuotaService,
    required CloudObservationService cloudObservationService,
  })  : _auth = auth,
        _firestore = firestore,
        _itemDao = itemDao,
        _locationDao = locationDao,
        _historyDao = historyDao,
        _syncCheckpointDao = syncCheckpointDao,
        _pendingSyncDao = pendingSyncDao,
        _imageUploadService = imageUploadService,
        _invoiceStorageService = invoiceStorageService,
        _itemCloudMediaService = itemCloudMediaService,
        _cloudQuotaService = cloudQuotaService,
        _cloudObservationService = cloudObservationService;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final ItemDao _itemDao;
  final LocationDao _locationDao;
  final HistoryDao _historyDao;
  final SyncCheckpointDao _syncCheckpointDao;
  final PendingSyncDao _pendingSyncDao;
  final FirebaseImageUploadService _imageUploadService;
  final FirebaseInvoiceStorageService _invoiceStorageService;
  final ItemCloudMediaService _itemCloudMediaService;
  final CloudQuotaService _cloudQuotaService;
  final CloudObservationService _cloudObservationService;

  DateTime? _lastSyncedAt;

  /// Prevents concurrent fullSync calls (auto sign-in sync + manual tap).
  bool _isFullSyncRunning = false;

  /// Whether a full sync is currently in progress. Exposed so callers can
  /// guard against double-sync.
  bool get isFullSyncRunning => _isFullSyncRunning;

  /// Hard timeout for the entire fullSync operation.
  static const _fullSyncTimeout = Duration(minutes: 5);

  /// Timeout for individual item sync (images + invoice + Firestore write).
  static const _perItemTimeout = Duration(seconds: 120);

  static const _usersCollection = 'users';
  static const _itemsCollection = 'items';
  static const _deletedItemsCollection = 'deleted_items';
  static const _locationsCollection = 'locations';
  static const _historyCollection = 'history';
  static const _personalBackupScope = 'personal_backup';
  static const _personalPendingSyncEntityType = 'personal_item';
  static const _deleteReasonDeleted = 'deleted';
  static const _deleteReasonBackupDisabled = 'backup_disabled';
  static const _deltaCheckpointMaxAge = Duration(days: 7);

  User? get _user => _auth.currentUser;

  DocumentReference<Map<String, dynamic>> get _userDoc {
    final user = _user;
    if (user == null) {
      throw StateError('Please sign in with Google to sync your backup data');
    }
    return _firestore.collection(_usersCollection).doc(user.uid);
  }

  CollectionReference<Map<String, dynamic>> get _itemsRef =>
      _userDoc.collection(_itemsCollection);

  CollectionReference<Map<String, dynamic>> get _deletedItemsRef =>
      _userDoc.collection(_deletedItemsCollection);

  CollectionReference<Map<String, dynamic>> get _locationsRef =>
      _userDoc.collection(_locationsCollection);

  @override
  Future<SyncResult> syncItem(Item item) async {
    return _syncItemInternal(
      item,
      ensureUserDocument: true,
      refreshUsageSnapshot: true,
    );
  }

  Future<SyncResult> _syncItemInternal(
    Item item, {
    required bool ensureUserDocument,
    required bool refreshUsageSnapshot,
  }) async {
    final user = _user;
    if (user == null) {
      return const SyncResult.error('Sign in to sync items to Firebase');
    }

    if (!item.isBackedUp) {
      return SyncResult.success();
    }

    // Wrap the entire per-item sync in a timeout so a single stalled upload
    // cannot block the whole fullSync indefinitely.
    try {
      return await _syncItemInternalGuarded(
        item,
        user,
        ensureUserDocument,
        refreshUsageSnapshot,
      ).timeout(_perItemTimeout, onTimeout: () {
        debugPrint(
          '[IkeepSync] TIMEOUT: item ${item.uuid} ("${item.name}") '
          'exceeded ${_perItemTimeout.inSeconds}s — aborting this item',
        );
        return SyncResult.error(
          'Sync timed out for "${item.name}" after '
          '${_perItemTimeout.inSeconds}s',
        );
      });
    } catch (e) {
      debugPrint('[IkeepSync] syncItem unexpected error for ${item.uuid}: $e');
      return SyncResult.error(e.toString());
    }
  }

  Future<SyncResult> _syncItemInternalGuarded(
    Item item,
    User user,
    bool ensureUserDocument,
    bool refreshUsageSnapshot,
  ) async {
    try {
      await _evaluateCloudQuotaForItem(item);

      final now = FieldValue.serverTimestamp();
      final syncedAt = DateTime.now();
      final sw = Stopwatch()..start();
      final existingImageReferences =
          await _itemCloudMediaService.getImageReferencesForItem(item.uuid);
      final existingInvoiceReference =
          await _itemCloudMediaService.getInvoiceReferenceForItem(item.uuid);
      final hadRemoteIdentity = _hasRemoteIdentity(item);
      final hasRemoteTombstone =
          hadRemoteIdentity ? await _remoteTombstoneExists(item.uuid) : false;
      final isNewRemoteItem = !hadRemoteIdentity || hasRemoteTombstone;
      final hasImageMediaChange = isNewRemoteItem ||
          _imageMediaNeedsSync(
            imagePaths: item.imagePaths,
            existingReferences: existingImageReferences,
          );
      final hasInvoiceMediaChange = isNewRemoteItem ||
          _invoiceMediaNeedsSync(
            invoicePath: item.invoicePath,
            existingReference: existingInvoiceReference,
          );
      final hasContentChange =
          isNewRemoteItem || _contentChangedSinceLastSync(item);
      final hasLocationChange =
          isNewRemoteItem || _locationChangedSinceLastSync(item);

      debugPrint(
        '[IkeepSync] syncItem START: uuid=${item.uuid} name="${item.name}" '
        'images=${item.imagePaths.length} '
        'hasInvoice=${item.invoicePath?.isNotEmpty ?? false} '
        'contentChanged=$hasContentChange '
        'locationChanged=$hasLocationChange '
        'hasRemoteTombstone=$hasRemoteTombstone '
        'mediaChanged=${hasImageMediaChange || hasInvoiceMediaChange}',
      );

      // ── Step 1: Upload images to Firebase Storage ────────────────────────
      ImageUploadResult? imageResult;
      if (hasImageMediaChange) {
        try {
          debugPrint(
            '[IkeepSync] [${sw.elapsedMilliseconds}ms] '
            'Image upload START for ${item.uuid}',
          );
          imageResult = await _imageUploadService.uploadItemImages(
            userId: user.uid,
            itemUuid: item.uuid,
            imagePaths: item.imagePaths,
          );
          debugPrint(
            '[IkeepSync] [${sw.elapsedMilliseconds}ms] Image upload END: '
            '${imageResult.downloadUrls.length} URL(s)',
          );
        } catch (e) {
          debugPrint(
            '[IkeepSync] [${sw.elapsedMilliseconds}ms] IMAGE UPLOAD FAILED '
            'for ${item.uuid}: $e',
          );
          imageResult = const ImageUploadResult(
            downloadUrls: [],
            storagePaths: [],
          );
        }
      } else {
        debugPrint(
          '[IkeepDelta] [${sw.elapsedMilliseconds}ms] '
          'skipped unchanged item images for ${item.uuid}',
        );
      }

      // ── Step 2: Upload invoice/PDF to Firebase Storage ───────────────────
      StoredInvoiceFile? uploadedInvoice;
      if (hasInvoiceMediaChange) {
        try {
          debugPrint(
            '[IkeepSync] [${sw.elapsedMilliseconds}ms] '
            'Invoice upload START for ${item.uuid}',
          );
          uploadedInvoice = await _invoiceStorageService.uploadItemInvoice(
            userId: user.uid,
            itemUuid: item.uuid,
            invoicePath: item.invoicePath,
            invoiceFileName: item.invoiceFileName,
            invoiceFileSizeBytes: item.invoiceFileSizeBytes,
          );
          debugPrint(
            '[IkeepSync] [${sw.elapsedMilliseconds}ms] Invoice upload END: '
            '${uploadedInvoice != null ? "uploaded" : "none"}',
          );
        } catch (e) {
          debugPrint(
            '[IkeepSync] [${sw.elapsedMilliseconds}ms] INVOICE UPLOAD FAILED '
            'for ${item.uuid}: $e',
          );
          uploadedInvoice = null;
        }
      } else {
        debugPrint(
          '[IkeepDelta] [${sw.elapsedMilliseconds}ms] '
          'skipped unchanged invoice for ${item.uuid}',
        );
      }

      // ── Step 3: Ensure user document exists (independent) ───────────────
      if (ensureUserDocument) {
        await _ensureUserDocument(user);
      }

      // ── Determine partial-failure state ──────────────────────────────────
      final hadImages = item.imagePaths.isNotEmpty;
      final hadInvoice = item.invoicePath?.trim().isNotEmpty ?? false;
      final imagesOk = !hadImages ||
          !hasImageMediaChange ||
          (imageResult?.hasImages ?? false);
      final invoiceOk =
          !hadInvoice || !hasInvoiceMediaChange || uploadedInvoice != null;
      final fullyUploaded = imagesOk && invoiceOk;

      if (!fullyUploaded) {
        debugPrint(
          '[IkeepSync] Partial upload for ${item.uuid} — '
          'imagesOk=$imagesOk invoiceOk=$invoiceOk',
        );
      }

      // ── Step 4: Write metadata + attachment URLs to Firestore ────────────
      debugPrint(
          '[IkeepSync] [${sw.elapsedMilliseconds}ms] Firestore write START for ${item.uuid}');

      final syncedItem = item.copyWith(
        cloudId: item.cloudId ?? item.uuid,
        lastSyncedAt: syncedAt,
        isBackedUp: true,
      );
      final firestorePatch = _buildFirestorePatch(
        item: syncedItem,
        userId: user.uid,
        serverSyncedAt: now,
        includeAllFields: isNewRemoteItem,
        includeContentFields: hasContentChange,
        includeLocationFields: hasLocationChange,
        includeImageFields: hasImageMediaChange,
        includeInvoiceFields: hasInvoiceMediaChange,
        imageResult: imageResult,
        uploadedInvoice: uploadedInvoice,
      );

      await _itemsRef
          .doc(item.uuid)
          .set(firestorePatch, SetOptions(merge: true));
      await _clearRemoteItemTombstone(item.uuid);

      debugPrint(
        '[IkeepSync] [${sw.elapsedMilliseconds}ms] Firestore write END for ${item.uuid}',
      );

      await _itemDao.updateItem(syncedItem);

      if (hasImageMediaChange || hasInvoiceMediaChange) {
        await _itemCloudMediaService.replaceForItemFromCloudData(
          itemUuid: item.uuid,
          data: _buildCombinedSidecarData(
            item: syncedItem,
            imageResult: imageResult,
            uploadedInvoice: uploadedInvoice,
            existingImageReferences: existingImageReferences,
            existingInvoiceReference: existingInvoiceReference,
          ),
        );
      }

      // ── Step 5: Sync location history to Firestore subcollection ──────
      if (hasLocationChange) {
        try {
          await _syncItemHistory(item.uuid);
        } catch (e) {
          debugPrint(
            '[IkeepSync] [${sw.elapsedMilliseconds}ms] HISTORY SYNC FAILED '
            'for ${item.uuid}: $e',
          );
        }
      }

      if (fullyUploaded) {
        await _clearPendingSyncForItem(item.uuid);
      }
      await _markPushCheckpointSucceeded();

      debugPrint(
        '[IkeepSync] syncItem COMPLETE for ${item.uuid} '
        'in ${sw.elapsedMilliseconds}ms (partial=${!fullyUploaded})',
      );
      sw.stop();

      _lastSyncedAt = syncedAt;
      if (refreshUsageSnapshot) {
        await _cloudQuotaService.refreshPersonalUsage();
      }
      await _recordUploadObservation(
        source: 'personal_item_sync',
        imageResult: imageResult,
        uploadedInvoice: uploadedInvoice,
      );
      return SyncResult.success(partialFailure: !fullyUploaded);
    } on SyncException catch (e) {
      debugPrint('[IkeepSync] syncItem quota error for ${item.uuid}: $e');
      return SyncResult.error(e.message);
    } catch (e) {
      debugPrint('[IkeepSync] syncItem error for ${item.uuid}: $e');
      return SyncResult.error(e.toString());
    }
  }

  @override
  Future<SyncResult> syncLocation(LocationModel location) async {
    return _syncLocationInternal(location, ensureUserDocument: true);
  }

  Future<SyncResult> _syncLocationInternal(
    LocationModel location, {
    required bool ensureUserDocument,
  }) async {
    final user = _user;
    if (user == null) {
      return const SyncResult.error('Sign in to sync locations to Firebase');
    }

    try {
      if (ensureUserDocument) {
        await _ensureUserDocument(user);
      }
      await _locationsRef.doc(location.uuid).set({
        ...location.toJson(),
        'userId': user.uid,
        'updatedAt': _toIsoString(DateTime.now()),
        'lastSyncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _markPushCheckpointSucceeded();
      _lastSyncedAt = DateTime.now();
      return SyncResult.success();
    } catch (e) {
      debugPrint('FirebaseSyncService.syncLocation error: $e');
      return SyncResult.error(e.toString());
    }
  }

  @override
  Future<SyncResult> deleteRemoteItem(
    String uuid, {
    String reason = 'deleted',
  }) async {
    final user = _user;
    if (user == null) {
      return const SyncResult.error('Sign in to sync items to Firebase');
    }

    try {
      await _ensureUserDocument(user);
      final cleanupErrors = <Object>[];

      Future<void> runCleanup(
        Future<void> Function() action,
        String label,
      ) async {
        try {
          await action();
        } catch (error) {
          if (_isMissingRemoteResource(error)) {
            return;
          }
          cleanupErrors.add(error);
          debugPrint(
            '[IkeepDelta] remote delete cleanup failed '
            'item=$uuid step=$label error=$error',
          );
        }
      }

      await runCleanup(
        () => _imageUploadService.deleteItemImages(
          userId: user.uid,
          itemUuid: uuid,
        ),
        'images',
      );
      await runCleanup(
        () => _invoiceStorageService.deleteItemInvoice(
          userId: user.uid,
          itemUuid: uuid,
        ),
        'invoice',
      );
      await runCleanup(
        () => _deleteRemoteItemHistory(uuid),
        'history',
      );

      final tombstone = _RemoteItemTombstone(
        itemUuid: uuid,
        deletedAt: DateTime.now(),
        reason: reason,
      );
      final batch = _firestore.batch();
      batch.set(
        _deletedItemsRef.doc(uuid),
        tombstone.toJson(),
        SetOptions(merge: true),
      );
      batch.delete(_itemsRef.doc(uuid));
      await batch.commit();

      await _clearPendingSyncForItem(uuid);
      await _markPushCheckpointSucceeded();
      _lastSyncedAt = DateTime.now();
      await _cloudQuotaService.refreshPersonalUsage();
      debugPrint(
        '[IkeepDelta] remote delete propagated '
        'item=$uuid reason=$reason partial=${cleanupErrors.isNotEmpty}',
      );
      return SyncResult.success(partialFailure: cleanupErrors.isNotEmpty);
    } catch (e) {
      if (_isMissingRemoteResource(e)) return SyncResult.success();
      return SyncResult.error(e.toString());
    }
  }

  @override
  Future<SyncResult> deleteRemoteLocation(String uuid) async {
    if (_user == null) {
      return const SyncResult.error('Sign in to sync locations to Firebase');
    }

    try {
      await _locationsRef.doc(uuid).delete();
      await _markPushCheckpointSucceeded();
      _lastSyncedAt = DateTime.now();
      return SyncResult.success();
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') return SyncResult.success();
      return SyncResult.error(e.message ?? 'Failed to delete remote location');
    } catch (e) {
      return SyncResult.error(e.toString());
    }
  }

  /// Maximum number of items synced to Firestore concurrently.
  static const _syncBatchSize = 5;

  @override
  Future<SyncResult> syncAll() async {
    if (_isFullSyncRunning) {
      debugPrint(
          '[IkeepDelta] syncAll skipped because another sync is running');
      return const SyncResult.syncing();
    }

    final user = _user;
    if (user == null) {
      return const SyncResult.error(
        'Please sign in with Google before syncing',
      );
    }

    _isFullSyncRunning = true;
    final syncSw = Stopwatch()..start();
    SyncResult? result;

    try {
      final checkpoint = await _loadCheckpoint();
      final fallbackReason = _fallbackReasonForCheckpoint(checkpoint);
      if (fallbackReason != null) {
        result = await _runFullSyncWithCheckpoint(
          user,
          syncSw,
          reason: fallbackReason,
        );
      } else {
        try {
          final deltaResult = await _deltaSyncGuarded(
            user,
            syncSw,
            checkpoint!,
          );
          if (!deltaResult.hasError && !deltaResult.isTimedOut) {
            await _cloudQuotaService.refreshPersonalUsage();
            result = deltaResult;
          } else {
            result = await _runFullSyncWithCheckpoint(
              user,
              syncSw,
              reason:
                  'delta_failed:${deltaResult.errorMessage ?? deltaResult.status.name}',
            );
          }
        } on _DeltaSyncFallbackException catch (error) {
          result = await _runFullSyncWithCheckpoint(
            user,
            syncSw,
            reason: error.reason,
          );
        } catch (error) {
          debugPrint(
            '[IkeepDelta] delta sync exception after '
            '${syncSw.elapsedMilliseconds}ms: $error',
          );
          result = await _runFullSyncWithCheckpoint(
            user,
            syncSw,
            reason: 'delta_exception',
          );
        }
      }
      return result!;
    } finally {
      _isFullSyncRunning = false;
      syncSw.stop();
      if (_shouldObserveSyncResult(result)) {
        await _observeSyncRun(
          source: 'personal_sync_all',
          result: result!,
        );
      }
    }
  }

  @override
  Future<SyncResult> fullSync() async {
    // ── Double-sync guard ──────────────────────────────────────────────────
    if (_isFullSyncRunning) {
      debugPrint('[IkeepSync] fullSync SKIPPED — already running');
      return const SyncResult.syncing();
    }

    final user = _user;
    if (user == null) {
      return const SyncResult.error(
          'Please sign in with Google before syncing');
    }

    _isFullSyncRunning = true;
    final syncSw = Stopwatch()..start();
    SyncResult? result;

    try {
      result = await _runFullSyncWithCheckpoint(
        user,
        syncSw,
        reason: 'explicit_full_sync',
      );
      return result!;
    } finally {
      _isFullSyncRunning = false;
      syncSw.stop();
      if (_shouldObserveSyncResult(result)) {
        await _observeSyncRun(
          source: 'personal_full_sync',
          result: result!,
        );
      }
    }
  }

  Future<SyncResult> _runFullSyncWithCheckpoint(
    User user,
    Stopwatch syncSw, {
    required String reason,
  }) async {
    debugPrint('[IkeepDelta] falling back to full sync reason=$reason');

    try {
      try {
        await _applyRemoteTombstonesForFullSyncRecovery();
      } catch (error) {
        debugPrint(
          '[IkeepDelta] tombstone recovery skipped before full sync: $error',
        );
      }

      final result = await _fullSyncGuarded(user, syncSw)
          .timeout(_fullSyncTimeout, onTimeout: () {
        debugPrint(
          '[IkeepSync] fullSync TIMEOUT after ${syncSw.elapsedMilliseconds}ms',
        );
        return SyncResult.timedOut(
          message: 'Full sync timed out after '
              '${_fullSyncTimeout.inMinutes} minutes',
        );
      });

      if (result.isSuccess) {
        await _cloudQuotaService.refreshPersonalUsage();
        final now = DateTime.now();
        final checkpoint = await _loadCheckpoint();
        try {
          await _saveCheckpoint(
            (checkpoint ??
                    SyncCheckpointState(
                      syncScope: _personalBackupScope,
                      updatedAt: now,
                    ))
                .copyWith(
              lastSuccessfulPullAt: now,
              lastSuccessfulPushAt: now,
              lastFullSyncAt: now,
              lastKnownRemoteCheckpoint: await _fetchLatestRemoteCheckpoint(),
              updatedAt: now,
            ),
          );
        } catch (error) {
          debugPrint('[IkeepDelta] full sync checkpoint save failed: $error');
        }
      }
      return result;
    } catch (error) {
      debugPrint(
        '[IkeepSync] fullSync ERROR after ${syncSw.elapsedMilliseconds}ms: '
        '$error',
      );
      return SyncResult.error(error.toString());
    }
  }

  Future<SyncCheckpointState?> _loadCheckpoint() async {
    final checkpoint =
        await _syncCheckpointDao.getByScope(_personalBackupScope);
    debugPrint(
      '[IkeepDelta] checkpoint load '
      'scope=$_personalBackupScope found=${checkpoint != null}',
    );
    return checkpoint;
  }

  Future<void> _saveCheckpoint(SyncCheckpointState checkpoint) async {
    await _syncCheckpointDao.upsert(checkpoint);
    debugPrint(
      '[IkeepDelta] checkpoint save scope=${checkpoint.syncScope} '
      'pull=${checkpoint.lastSuccessfulPullAt?.toIso8601String()} '
      'push=${checkpoint.lastSuccessfulPushAt?.toIso8601String()} '
      'full=${checkpoint.lastFullSyncAt?.toIso8601String()} '
      'remote=${checkpoint.lastKnownRemoteCheckpoint}',
    );
  }

  String? _fallbackReasonForCheckpoint(SyncCheckpointState? checkpoint) {
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

    final now = DateTime.now();
    if (lastFullSyncAt.isAfter(now.add(const Duration(minutes: 5)))) {
      return 'future_full_sync_anchor';
    }

    if (now.difference(lastFullSyncAt) > _deltaCheckpointMaxAge) {
      return 'stale_full_sync_anchor';
    }

    return null;
  }

  Future<String?> _fetchLatestRemoteCheckpoint() async {
    try {
      final results = await Future.wait([
        _itemsRef.orderBy('updatedAt', descending: true).limit(1).get(),
        _deletedItemsRef.orderBy('deletedAt', descending: true).limit(1).get(),
      ]);

      final itemSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final tombstoneSnapshot =
          results[1] as QuerySnapshot<Map<String, dynamic>>;
      final candidates = <String>[
        if (itemSnapshot.docs.isNotEmpty)
          ((itemSnapshot.docs.first.data()['updatedAt'] as String?) ?? '')
              .trim(),
        if (tombstoneSnapshot.docs.isNotEmpty)
          ((tombstoneSnapshot.docs.first.data()['deletedAt'] as String?) ?? '')
              .trim(),
      ].where((value) => value.isNotEmpty).toList(growable: false);

      if (candidates.isEmpty) {
        return null;
      }

      candidates.sort();
      return candidates.last;
    } catch (error) {
      debugPrint('[IkeepDelta] remote checkpoint fetch failed: $error');
      return null;
    }
  }

  Future<SyncResult> _deltaSyncGuarded(
    User user,
    Stopwatch syncSw,
    SyncCheckpointState checkpoint,
  ) async {
    debugPrint('[IkeepDelta] delta sync start');

    await _ensureUserDocument(user);

    final pullOutcome = await _pullRemoteItemDeltas(
      syncSw: syncSw,
      checkpoint: checkpoint,
    );
    final pushOutcome = await _pushLocalItemDeltas(syncSw: syncSw);

    final now = DateTime.now();
    final remoteCheckpoint = await _fetchLatestRemoteCheckpoint() ??
        checkpoint.lastKnownRemoteCheckpoint;
    try {
      await _saveCheckpoint(
        checkpoint.copyWith(
          lastSuccessfulPullAt:
              pullOutcome.success ? now : checkpoint.lastSuccessfulPullAt,
          lastSuccessfulPushAt:
              pushOutcome.success ? now : checkpoint.lastSuccessfulPushAt,
          lastKnownRemoteCheckpoint: remoteCheckpoint,
          updatedAt: now,
        ),
      );
    } catch (error) {
      debugPrint('[IkeepDelta] delta checkpoint save failed: $error');
    }

    final pulledChanges = pullOutcome.importedCount +
        pullOutcome.deletedCount +
        pullOutcome.convertedCount;
    final totalItems =
        pulledChanges + pushOutcome.syncedItems + pushOutcome.deletedItems;
    final failedItems = pushOutcome.failedItems;
    final partialFailure = failedItems > 0;

    debugPrint(
      '[IkeepDelta] delta sync complete '
      'pulled=${pullOutcome.importedCount} '
      'remoteDeleted=${pullOutcome.deletedCount} '
      'remoteUnbacked=${pullOutcome.convertedCount} '
      'pushed=${pushOutcome.syncedItems} '
      'deleted=${pushOutcome.deletedItems} '
      'skipped=${pushOutcome.skippedItems} '
      'failed=$failedItems',
    );

    _lastSyncedAt = now;
    return SyncResult.success(
      partialFailure: partialFailure,
      totalItems: totalItems,
      syncedItems: pulledChanges + pushOutcome.syncedItems,
      failedItems: failedItems,
      itemOutcomes: pushOutcome.itemOutcomes,
    );
  }

  Future<SyncResult> _fullSyncGuarded(User user, Stopwatch syncSw) async {
    try {
      debugPrint('[IkeepSync] fullSync START');

      // Kick off all independent fetches in parallel.
      debugPrint(
          '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] Fetching local + remote data...');
      final results = await Future.wait([
        _ensureUserDocument(user), // 0
        _locationDao.recalculateUsageCounts(), // 1
        _locationDao.getAllLocations(), // 2
        _itemDao.getAllItems(includeArchived: true), // 3
        _locationsRef.get(), // 4
        _itemsRef.get(), // 5
      ]);
      debugPrint(
          '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] Data fetch complete');

      final localLocations = results[2] as List<LocationModel>;
      final localItems = results[3] as List<Item>;
      final remoteLocationsSnapshot =
          results[4] as QuerySnapshot<Map<String, dynamic>>;
      final remoteItemsSnapshot =
          results[5] as QuerySnapshot<Map<String, dynamic>>;

      final remoteLocations = {
        for (final doc in remoteLocationsSnapshot.docs) doc.id: doc.data(),
      };
      final remoteItems = {
        for (final doc in remoteItemsSnapshot.docs) doc.id: doc.data(),
      };

      // ── Locations: batch writes to Firestore, parallel local inserts ──
      debugPrint(
          '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] Syncing locations...');
      final locationBatch = _firestore.batch();
      final localLocationUpserts = <LocationModel>[];
      final existingLocalLocationUuids =
          localLocations.map((loc) => loc.uuid).toSet();
      var locationBatchCount = 0;

      for (final location in localLocations) {
        final remoteData = remoteLocations[location.uuid];
        if (remoteData == null) {
          _addLocationToBatch(locationBatch, location, user);
          locationBatchCount++;
          continue;
        }
        if (_isLocationInSync(location, remoteData)) continue;

        final remoteUpdatedAt = _parseDateTime(remoteData['updatedAt']);
        final localUpdatedAt = location.createdAt;
        if (remoteUpdatedAt != null &&
            remoteUpdatedAt.isAfter(localUpdatedAt)) {
          localLocationUpserts.add(_locationFromFirestore(remoteData));
        } else {
          _addLocationToBatch(locationBatch, location, user);
          locationBatchCount++;
        }
      }

      for (final remoteEntry in remoteLocations.entries) {
        final existsLocally =
            localLocations.any((loc) => loc.uuid == remoteEntry.key);
        if (!existsLocally) {
          localLocationUpserts.add(_locationFromFirestore(remoteEntry.value));
        }
      }

      await Future.wait([
        if (locationBatchCount > 0) locationBatch.commit(),
        _upsertLocationsLocally(
          localLocationUpserts,
          existingLocationUuids: existingLocalLocationUuids,
        ),
      ]);
      debugPrint(
          '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] Locations synced');

      // ── Categorise items ──────────────────────────────────────────────
      final itemsToUpload = <Item>[];
      final itemsToDelete = <String>[];
      final itemsToImportLocally = <Map<String, dynamic>>[];

      for (final item in localItems) {
        final remoteData = remoteItems[item.uuid];
        final localUpdatedAt = item.updatedAt ?? item.savedAt;

        if (!item.isBackedUp) {
          if (remoteData != null) itemsToDelete.add(item.uuid);
          continue;
        }

        if (remoteData == null) {
          itemsToUpload.add(item);
          continue;
        }

        final remoteUpdatedAt = _parseDateTime(remoteData['updatedAt']) ??
            _parseDateTime(remoteData['savedAt']);
        if (_isItemInSync(
          item: item,
          localUpdatedAt: localUpdatedAt,
          remoteUpdatedAt: remoteUpdatedAt,
        )) {
          continue;
        }
        if (remoteUpdatedAt != null &&
            remoteUpdatedAt.isAfter(localUpdatedAt)) {
          itemsToImportLocally.add(remoteData);
        } else {
          itemsToUpload.add(item);
        }
      }

      for (final remoteEntry in remoteItems.entries) {
        final existsLocally =
            localItems.any((item) => item.uuid == remoteEntry.key);
        if (!existsLocally) {
          itemsToImportLocally.add(remoteEntry.value);
        }
      }

      final totalItemOps = itemsToUpload.length +
          itemsToImportLocally.length +
          itemsToDelete.length;
      debugPrint(
        '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] Item plan: '
        'upload=${itemsToUpload.length} import=${itemsToImportLocally.length} '
        'delete=${itemsToDelete.length} total=$totalItemOps',
      );

      // ── Import remote-only items locally ──────────────────────────────
      var importedCount = 0;
      final importedItemUuids = <String>[];
      for (var i = 0; i < itemsToImportLocally.length; i += _syncBatchSize) {
        final batch = itemsToImportLocally.skip(i).take(_syncBatchSize);
        await Future.wait(
          batch.map((data) async {
            try {
              final restoredItem = _itemFromFirestore(data);
              final existing = await _itemDao.getItemByUuid(restoredItem.uuid);
              if (existing != null) {
                await _itemDao.updateItem(restoredItem);
              } else {
                await _itemDao.insertItem(restoredItem);
              }
              await _itemCloudMediaService.replaceForItemFromCloudData(
                itemUuid: restoredItem.uuid,
                data: data,
              );
              importedItemUuids.add(restoredItem.uuid);
              importedCount++;
            } catch (e) {
              debugPrint(
                '[IkeepSync] Failed to import item ${data['uuid']}: $e',
              );
            }
          }),
        );
      }
      if (itemsToImportLocally.isNotEmpty) {
        debugPrint(
          '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] '
          'Imported $importedCount/${itemsToImportLocally.length} items',
        );
      }

      // ── Restore location history for imported items ────────────────
      if (importedItemUuids.isNotEmpty) {
        debugPrint(
          '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] '
          'Restoring history for ${importedItemUuids.length} imported item(s)...',
        );
        for (final itemUuid in importedItemUuids) {
          try {
            await _restoreItemHistory(itemUuid);
          } catch (e) {
            debugPrint(
              '[IkeepSync] History restore failed for $itemUuid: $e',
            );
          }
        }
        debugPrint(
          '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] History restore complete',
        );
      }

      // ── Delete un-backed-up items from remote ─────────────────────────
      if (itemsToDelete.isNotEmpty) {
        debugPrint(
          '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] '
          'Deleting ${itemsToDelete.length} remote items...',
        );
        await Future.wait(
          itemsToDelete.map(
            (uuid) => deleteRemoteItem(
              uuid,
              reason: _deleteReasonBackupDisabled,
            ),
          ),
        );
        debugPrint(
          '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] Remote deletes done',
        );
      }

      // ── Upload items with per-item tracking ───────────────────────────
      final itemOutcomes = <ItemSyncOutcome>[];
      var uploadedOk = 0;
      var uploadedFail = 0;

      for (var i = 0; i < itemsToUpload.length; i += _syncBatchSize) {
        final batchItems = itemsToUpload.skip(i).take(_syncBatchSize).toList();
        final batchStart = i + 1;
        final batchEnd = (i + batchItems.length);
        debugPrint(
          '[IkeepSync] [${syncSw.elapsedMilliseconds}ms] '
          'Upload batch $batchStart–$batchEnd of ${itemsToUpload.length}',
        );

        final batchResults = await Future.wait(
          batchItems.map(
            (item) => _syncItemInternal(
              item,
              ensureUserDocument: false,
              refreshUsageSnapshot: false,
            ),
          ),
        );

        for (var j = 0; j < batchItems.length; j++) {
          final item = batchItems[j];
          final result = batchResults[j];
          final ok = result.isSuccess;
          if (ok) {
            uploadedOk++;
          } else {
            uploadedFail++;
          }
          itemOutcomes.add(ItemSyncOutcome(
            itemUuid: item.uuid,
            itemName: item.name,
            success: ok,
            partialFailure: result.partialFailure,
            errorMessage: result.errorMessage,
          ));
          debugPrint(
            '[IkeepSync]   item ${i + j + 1}/${itemsToUpload.length} '
            '"${item.name}" → ${ok ? "OK" : "FAIL"}',
          );
        }
      }

      await _locationDao.recalculateUsageCounts();

      _lastSyncedAt = DateTime.now();
      await _userDoc.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'lastSyncedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final hasPartialFailure =
          itemOutcomes.any((o) => o.partialFailure || !o.success);

      debugPrint(
        '[IkeepSync] fullSync COMPLETE in ${syncSw.elapsedMilliseconds}ms — '
        'uploaded=$uploadedOk failed=$uploadedFail '
        'imported=$importedCount deleted=${itemsToDelete.length}',
      );

      return SyncResult.success(
        partialFailure: hasPartialFailure,
        totalItems: totalItemOps,
        syncedItems: uploadedOk + importedCount,
        failedItems: uploadedFail,
        itemOutcomes: itemOutcomes,
      );
    } catch (e) {
      debugPrint(
        '[IkeepSync] fullSync error at ${syncSw.elapsedMilliseconds}ms: $e',
      );
      return SyncResult.error(e.toString());
    }
  }

  Future<_DeltaPullOutcome> _pullRemoteItemDeltas({
    required Stopwatch syncSw,
    required SyncCheckpointState checkpoint,
  }) async {
    final remoteCursor = checkpoint.lastKnownRemoteCheckpoint?.trim();
    if (remoteCursor == null || remoteCursor.isEmpty) {
      throw const _DeltaSyncFallbackException('missing_remote_checkpoint');
    }

    final results = await Future.wait([
      _itemsRef
          .where('updatedAt', isGreaterThan: remoteCursor)
          .orderBy('updatedAt')
          .get(),
      _deletedItemsRef
          .where('deletedAt', isGreaterThan: remoteCursor)
          .orderBy('deletedAt')
          .get(),
    ]);
    final itemSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final tombstoneSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final events = <_RemoteDeltaEvent>[];

    for (final doc in itemSnapshot.docs) {
      final data = doc.data();
      final remoteUuid = ((data['uuid'] as String?) ?? doc.id).trim();
      final changedAt = _parseDateTime(data['updatedAt']);
      if (remoteUuid.isEmpty || changedAt == null) {
        throw const _DeltaSyncFallbackException('remote_schema_mismatch');
      }
      events.add(
        _RemoteDeltaEvent.item(
          itemUuid: remoteUuid,
          changedAt: changedAt,
          data: data,
        ),
      );
    }

    for (final doc in tombstoneSnapshot.docs) {
      final tombstone = _remoteTombstoneFromData(doc.id, doc.data());
      if (tombstone == null) {
        throw const _DeltaSyncFallbackException(
            'remote_tombstone_schema_mismatch');
      }
      events.add(_RemoteDeltaEvent.tombstone(tombstone: tombstone));
    }

    events.sort((a, b) => a.changedAt.compareTo(b.changedAt));
    debugPrint(
      '[IkeepDelta] delta pull '
      'items=${itemSnapshot.docs.length} '
      'tombstones=${tombstoneSnapshot.docs.length} '
      'events=${events.length} '
      'since=$remoteCursor '
      'after=${syncSw.elapsedMilliseconds}ms',
    );

    var importedCount = 0;
    var deletedCount = 0;
    var convertedCount = 0;
    for (final event in events) {
      final tombstone = event.tombstone;
      if (tombstone != null) {
        final outcome = await _applyRemoteItemTombstone(
          tombstone: tombstone,
          source: 'delta_pull',
        );
        if (outcome.deletedLocally) {
          deletedCount++;
        }
        if (outcome.convertedToLocalOnly) {
          convertedCount++;
        }
        continue;
      }

      final data = event.data!;
      final remoteItem = _itemFromFirestore(data);
      await _ensureLocationsForItem(remoteItem);
      final localItem = await _itemDao.getItemByUuid(remoteItem.uuid);

      if (localItem == null) {
        await _itemDao.insertItem(remoteItem);
        await _itemCloudMediaService.replaceForItemFromCloudData(
          itemUuid: remoteItem.uuid,
          data: data,
        );
        if (remoteItem.lastMovedAt != null) {
          try {
            await _restoreItemHistory(remoteItem.uuid);
          } catch (error) {
            debugPrint(
              '[IkeepDelta] remote history restore failed '
              'for ${remoteItem.uuid}: $error',
            );
          }
        }
        importedCount++;
        continue;
      }

      if (!localItem.isBackedUp && _hasRemoteIdentity(localItem)) {
        debugPrint(
          '[IkeepDelta] preserving local backup-off state for ${localItem.uuid}',
        );
        continue;
      }

      final localImageReferences = await _itemCloudMediaService
          .getImageReferencesForItem(localItem.uuid);
      final localInvoiceReference = await _itemCloudMediaService
          .getInvoiceReferenceForItem(localItem.uuid);
      final mergeOutcome = _mergeRemoteItemDelta(
        localItem: localItem,
        remoteItem: remoteItem,
        remoteData: data,
        localImageReferences: localImageReferences,
        localInvoiceReference: localInvoiceReference,
      );

      await _itemDao.updateItem(mergeOutcome.mergedItem);
      if (mergeOutcome.replaceSidecarFromRemote) {
        await _itemCloudMediaService.replaceForItemFromCloudData(
          itemUuid: mergeOutcome.mergedItem.uuid,
          data: data,
        );
      }
      if (mergeOutcome.restoreHistoryFromRemote) {
        try {
          await _restoreItemHistory(mergeOutcome.mergedItem.uuid);
        } catch (error) {
          debugPrint(
            '[IkeepDelta] merged history restore failed '
            'for ${mergeOutcome.mergedItem.uuid}: $error',
          );
        }
      }
      importedCount++;
    }

    if (importedCount > 0 || deletedCount > 0 || convertedCount > 0) {
      await _locationDao.recalculateUsageCounts();
    }

    return _DeltaPullOutcome(
      success: true,
      importedCount: importedCount,
      deletedCount: deletedCount,
      convertedCount: convertedCount,
    );
  }

  Future<_DeltaPushOutcome> _pushLocalItemDeltas({
    required Stopwatch syncSw,
  }) async {
    final localItems = await _itemDao.getAllItems(includeArchived: true);
    final localItemsByUuid = {
      for (final item in localItems) item.uuid: item,
    };
    final queuedOperations =
        await _pendingSyncDao.getByEntityType(_personalPendingSyncEntityType);
    final queuedUuids = <String>{};
    final itemsToPush = <String, Item>{};
    final deleteRequests = <String, _QueuedDeleteRequest>{};
    var skippedItems = 0;
    var queueSelectedPushes = 0;
    var queueSelectedDeletes = 0;
    var timestampFallbackPushes = 0;
    var timestampFallbackDeletes = 0;

    // Queue-backed selection is primary in Phase 5B. Timestamp scanning only
    // fills gaps when a local change was not enqueued for any reason.
    for (final operation in queuedOperations) {
      queuedUuids.add(operation.entityUuid);
      final localItem = localItemsByUuid[operation.entityUuid];
      final itemName = (operation.payload['itemName'] as String?) ??
          localItem?.name ??
          operation.entityUuid;
      final deleteReason =
          (operation.payload['reason'] as String?) ?? _deleteReasonDeleted;

      if (operation.operationType == 'delete') {
        final hadRemoteIdentity =
            (operation.payload['hadRemoteIdentity'] as bool?) ??
                (localItem != null && _hasRemoteIdentity(localItem));
        if (!hadRemoteIdentity) {
          await _clearPendingSyncForItem(operation.entityUuid);
          skippedItems++;
          debugPrint(
            '[IkeepDelta] dropped stale queued delete '
            'item=${operation.entityUuid}',
          );
          continue;
        }

        deleteRequests[operation.entityUuid] = _QueuedDeleteRequest(
          itemUuid: operation.entityUuid,
          itemName: itemName,
          reason: deleteReason,
        );
        queueSelectedDeletes++;
        debugPrint(
          '[IkeepDelta] queue-selected delete '
          'item=${operation.entityUuid} reason=$deleteReason',
        );
        continue;
      }

      if (operation.operationType != 'upsert') {
        skippedItems++;
        debugPrint(
          '[IkeepDelta] ignored unknown queued op '
          'item=${operation.entityUuid} op=${operation.operationType}',
        );
        continue;
      }

      if (localItem == null) {
        await _clearPendingSyncForItem(operation.entityUuid);
        skippedItems++;
        debugPrint(
          '[IkeepDelta] dropped stale queued upsert '
          'item=${operation.entityUuid}',
        );
        continue;
      }

      if (!localItem.isBackedUp) {
        if (_hasRemoteIdentity(localItem)) {
          deleteRequests[localItem.uuid] = _QueuedDeleteRequest(
            itemUuid: localItem.uuid,
            itemName: localItem.name,
            reason: _deleteReasonBackupDisabled,
          );
          queueSelectedDeletes++;
          debugPrint(
            '[IkeepDelta] queue upsert downgraded to delete '
            'item=${localItem.uuid} reason=$_deleteReasonBackupDisabled',
          );
        } else {
          await _clearPendingSyncForItem(localItem.uuid);
          skippedItems++;
        }
        continue;
      }

      itemsToPush[localItem.uuid] = localItem;
      queueSelectedPushes++;
      debugPrint(
        '[IkeepDelta] queue-selected upsert item=${localItem.uuid}',
      );
    }

    for (final item in localItems) {
      if (queuedUuids.contains(item.uuid)) {
        continue;
      }

      if (!item.isBackedUp) {
        if (_hasRemoteIdentity(item)) {
          deleteRequests[item.uuid] = _QueuedDeleteRequest(
            itemUuid: item.uuid,
            itemName: item.name,
            reason: _deleteReasonBackupDisabled,
          );
          timestampFallbackDeletes++;
          debugPrint(
            '[IkeepDelta] timestamp-selected delete '
            'item=${item.uuid} reason=$_deleteReasonBackupDisabled',
          );
        } else {
          skippedItems++;
        }
        continue;
      }

      if (_localItemNeedsDeltaPush(item)) {
        itemsToPush[item.uuid] = item;
        timestampFallbackPushes++;
        debugPrint(
          '[IkeepDelta] timestamp-selected upsert item=${item.uuid}',
        );
      } else {
        skippedItems++;
      }
    }

    debugPrint(
      '[IkeepDelta] delta push plan '
      'queuePush=$queueSelectedPushes '
      'queueDelete=$queueSelectedDeletes '
      'timestampPush=$timestampFallbackPushes '
      'timestampDelete=$timestampFallbackDeletes '
      'push=${itemsToPush.length} '
      'delete=${deleteRequests.length} '
      'skipped=$skippedItems',
    );

    var syncedItems = 0;
    var deletedItems = 0;
    var failedItems = 0;
    final itemOutcomes = <ItemSyncOutcome>[];

    for (final request in deleteRequests.values) {
      final result = await deleteRemoteItem(
        request.itemUuid,
        reason: request.reason,
      );
      if (result.isSuccess) {
        deletedItems++;
        itemOutcomes.add(ItemSyncOutcome(
          itemUuid: request.itemUuid,
          itemName: request.itemName,
          success: true,
          partialFailure: result.partialFailure,
        ));
      } else {
        failedItems++;
        itemOutcomes.add(ItemSyncOutcome(
          itemUuid: request.itemUuid,
          itemName: request.itemName,
          success: false,
          errorMessage: result.errorMessage,
        ));
      }
    }

    final itemsToPushList = itemsToPush.values.toList(growable: false);
    for (var i = 0; i < itemsToPushList.length; i += _syncBatchSize) {
      final batchItems = itemsToPushList.skip(i).take(_syncBatchSize).toList();
      debugPrint(
        '[IkeepDelta] [${syncSw.elapsedMilliseconds}ms] '
        'delta push batch ${i + 1}-${i + batchItems.length} '
        'of ${itemsToPushList.length}',
      );
      final results = await Future.wait(
        batchItems.map(
          (item) => _syncItemInternal(
            item,
            ensureUserDocument: false,
            refreshUsageSnapshot: false,
          ),
        ),
      );
      for (var index = 0; index < batchItems.length; index++) {
        final item = batchItems[index];
        final result = results[index];
        if (result.isSuccess) {
          syncedItems++;
        } else {
          failedItems++;
        }
        itemOutcomes.add(ItemSyncOutcome(
          itemUuid: item.uuid,
          itemName: item.name,
          success: result.isSuccess,
          partialFailure: result.partialFailure,
          errorMessage: result.errorMessage,
        ));
      }
    }

    return _DeltaPushOutcome(
      success: failedItems == 0,
      syncedItems: syncedItems,
      deletedItems: deletedItems,
      skippedItems: skippedItems,
      failedItems: failedItems,
      itemOutcomes: itemOutcomes,
    );
  }

  /// Merges a changed remote item into the local SQLite source of truth.
  ///
  /// Conflict rules stay intentionally simple in Phase 5B:
  /// - Content fields use `lastContentUpdatedAt`/`lastUpdatedAt`.
  /// - Location fields use `lastMovedAt`.
  /// - Media never gets overwritten by a remote metadata-only edit.
  /// - Locally dirty media wins until a later push confirms replacement.
  _DeltaMergeOutcome _mergeRemoteItemDelta({
    required Item localItem,
    required Item remoteItem,
    required Map<String, dynamic> remoteData,
    required List<ItemCloudMediaReference> localImageReferences,
    required ItemCloudMediaReference? localInvoiceReference,
  }) {
    final localContentAt = _contentTimestamp(localItem);
    final remoteContentAt = _remoteContentTimestamp(remoteData, remoteItem);
    final localLocationAt = localItem.lastMovedAt;
    final remoteLocationAt = remoteItem.lastMovedAt;
    final localMediaDirty = _imageMediaNeedsSync(
          imagePaths: localItem.imagePaths,
          existingReferences: localImageReferences,
        ) ||
        _invoiceMediaNeedsSync(
          invoicePath: localItem.invoicePath,
          existingReference: localInvoiceReference,
        );
    final remoteMediaAt = _remoteMediaTimestamp(remoteData);

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

    final localWinsContent = _isLocalNewer(
      localChangeAt: localContentAt,
      remoteChangeAt: remoteContentAt,
    );
    final localWinsLocation = _isLocalNewer(
      localChangeAt: localLocationAt,
      remoteChangeAt: remoteLocationAt,
    );
    final localWinsMedia = localMediaDirty;

    final useRemoteContent = remoteContentChanged && !localWinsContent;
    final useRemoteLocation = remoteLocationChanged && !localWinsLocation;
    final useRemoteMedia = remoteMediaChanged && !localWinsMedia;

    var mergedItem = localItem.copyWith(
      cloudId: remoteItem.cloudId ?? localItem.cloudId ?? localItem.uuid,
      isBackedUp: true,
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

    final requiresPush =
        localWinsContent || localWinsLocation || localWinsMedia;
    mergedItem = mergedItem.copyWith(
      lastSyncedAt: requiresPush ? localItem.lastSyncedAt : DateTime.now(),
    );

    debugPrint(
      '[IkeepDelta] conflict item=${localItem.uuid} '
      'content=${useRemoteContent ? "remote" : localWinsContent ? "local" : "same"} '
      'location=${useRemoteLocation ? "remote" : localWinsLocation ? "local" : "same"} '
      'media=${useRemoteMedia ? "remote" : localWinsMedia ? "local" : "same"}',
    );

    return _DeltaMergeOutcome(
      mergedItem: mergedItem,
      replaceSidecarFromRemote: useRemoteMedia,
      restoreHistoryFromRemote: useRemoteLocation,
    );
  }

  Future<void> _ensureLocationsForItem(Item item) async {
    final referencedUuids = <String>{
      if (item.locationUuid?.trim().isNotEmpty ?? false)
        item.locationUuid!.trim(),
      if (item.areaUuid?.trim().isNotEmpty ?? false) item.areaUuid!.trim(),
      if (item.roomUuid?.trim().isNotEmpty ?? false) item.roomUuid!.trim(),
      if (item.zoneUuid?.trim().isNotEmpty ?? false) item.zoneUuid!.trim(),
    };
    if (referencedUuids.isEmpty) {
      return;
    }

    final missingLocations = <LocationModel>[];
    for (final uuid in referencedUuids) {
      final existing = await _locationDao.getLocationByUuid(uuid);
      if (existing != null) {
        continue;
      }

      final snapshot = await _locationsRef.doc(uuid).get();
      final data = snapshot.data();
      if (data == null) {
        continue;
      }
      missingLocations.add(_locationFromFirestore(data));
    }

    if (missingLocations.isEmpty) {
      return;
    }

    final existingLocalUuids = (await _locationDao.getAllLocations())
        .map((location) => location.uuid)
        .toSet();
    await _upsertLocationsLocally(
      missingLocations,
      existingLocationUuids: existingLocalUuids,
    );
  }

  Map<String, dynamic> _buildFirestorePatch({
    required Item item,
    required String userId,
    required Object serverSyncedAt,
    required bool includeAllFields,
    required bool includeContentFields,
    required bool includeLocationFields,
    required bool includeImageFields,
    required bool includeInvoiceFields,
    required ImageUploadResult? imageResult,
    required StoredInvoiceFile? uploadedInvoice,
  }) {
    final contentAt = _contentTimestamp(item);
    final patch = <String, dynamic>{
      'lastSyncedAt': serverSyncedAt,
    };

    if (includeAllFields) {
      patch.addAll({
        'uuid': item.uuid,
        'cloudId': item.cloudId ?? item.uuid,
        'userId': userId,
        'itemId': item.uuid,
        'ownerUid': userId,
        'isBackedUp': true,
      });
    }

    if (includeAllFields ||
        includeContentFields ||
        includeLocationFields ||
        includeImageFields ||
        includeInvoiceFields) {
      patch['updatedAt'] = _toIsoString(item.updatedAt ?? DateTime.now());
    }

    if (includeAllFields) {
      patch['savedAt'] = _toIsoString(item.savedAt);
      patch['createdAt'] = _toIsoString(item.savedAt);
    }

    if (includeAllFields || includeContentFields) {
      patch.addAll({
        'name': item.name,
        'tags': item.tags,
        'isArchived': item.isArchived,
        'notes': item.notes,
        'isLent': item.isLent,
        'lentTo': item.lentTo,
        'lentOn': item.lentOn?.toIso8601String(),
        'expectedReturnDate': item.expectedReturnDate?.toIso8601String(),
        'seasonCategory': item.seasonCategory,
        'lentReminderAfterDays': item.lentReminderAfterDays,
        'isAvailableForLending': item.isAvailableForLending,
        'expiryDate': item.expiryDate?.toIso8601String(),
        'warrantyEndDate': item.warrantyEndDate?.toIso8601String(),
        'visibility': item.visibility.value,
        'householdId': item.householdId,
        'sharedWithMemberUuids': item.sharedWithMemberUuids,
        'title': item.name,
        'note': item.notes,
        'lastUpdatedAt': item.lastUpdatedAt?.toIso8601String(),
        'lastContentUpdatedAt': _toIsoString(contentAt),
        'syncVersion':
            contentAt.millisecondsSinceEpoch.clamp(1, 1 << 62).toInt(),
      });
    }

    if (includeAllFields || includeLocationFields) {
      patch.addAll({
        'locationUuid': item.locationUuid,
        'areaUuid': item.areaUuid,
        'roomUuid': item.roomUuid,
        'zoneUuid': item.zoneUuid,
        'latitude': item.latitude,
        'longitude': item.longitude,
        'lastMovedAt': item.lastMovedAt?.toIso8601String(),
      });
    }

    if (includeAllFields || includeImageFields) {
      patch.addAll({
        'imagePaths': imageResult?.downloadUrls ?? const <String>[],
        'imageStoragePaths': imageResult?.storagePaths ?? const <String>[],
        'imageMedia': imageResult?.mediaDescriptors
                .map((descriptor) => descriptor.toJson())
                .toList() ??
            const <Map<String, dynamic>>[],
      });
    }

    if (includeAllFields || includeInvoiceFields) {
      final hasInvoice = item.invoicePath?.trim().isNotEmpty ?? false;
      patch.addAll({
        'invoicePath': hasInvoice ? uploadedInvoice?.path : null,
        'invoiceFileName': hasInvoice
            ? (uploadedInvoice?.fileName ?? item.invoiceFileName)
            : null,
        'invoiceFileSizeBytes': hasInvoice
            ? (uploadedInvoice?.sizeBytes ?? item.invoiceFileSizeBytes)
            : null,
        'invoiceStoragePath': hasInvoice ? uploadedInvoice?.storagePath : null,
        'invoiceMedia':
            hasInvoice ? uploadedInvoice?.mediaDescriptor?.toJson() : null,
        'invoiceOriginalFileName':
            hasInvoice ? uploadedInvoice?.originalFileName : null,
        'invoiceOriginalFileSizeBytes':
            hasInvoice ? uploadedInvoice?.originalFileSizeBytes : null,
        'invoiceUploadedFileSizeBytes':
            hasInvoice ? uploadedInvoice?.sizeBytes : null,
        'invoiceMimeType': hasInvoice ? uploadedInvoice?.mimeType : null,
        'invoiceCompressionApplied':
            hasInvoice ? uploadedInvoice?.compressionApplied : null,
        'invoiceUploadedAt': hasInvoice ? FieldValue.serverTimestamp() : null,
      });
    }

    return patch;
  }

  Map<String, dynamic> _buildCombinedSidecarData({
    required Item item,
    required ImageUploadResult? imageResult,
    required StoredInvoiceFile? uploadedInvoice,
    required List<ItemCloudMediaReference> existingImageReferences,
    required ItemCloudMediaReference? existingInvoiceReference,
  }) {
    final contentAt = _contentTimestamp(item);
    final imageDescriptors = (item.imagePaths.isEmpty
            ? const <CloudMediaDescriptor>[]
            : imageResult?.mediaDescriptors ??
                existingImageReferences
                    .map((reference) => reference.toDescriptor())
                    .toList(growable: false))
        .map((descriptor) => descriptor.toJson())
        .toList(growable: false);
    final hasInvoice = item.invoicePath?.trim().isNotEmpty ?? false;
    final invoiceDescriptor = hasInvoice
        ? (uploadedInvoice?.mediaDescriptor ??
            existingInvoiceReference?.toDescriptor())
        : null;

    return {
      'updatedAt': _toIsoString(item.updatedAt ?? item.savedAt),
      'createdAt': _toIsoString(item.savedAt),
      'lastContentUpdatedAt': _toIsoString(contentAt),
      'syncVersion': contentAt.millisecondsSinceEpoch.clamp(1, 1 << 62).toInt(),
      'imageMedia': imageDescriptors,
      'invoiceMedia': invoiceDescriptor?.toJson(),
    };
  }

  Future<void> _markPushCheckpointSucceeded() async {
    try {
      final now = DateTime.now();
      final checkpoint = await _loadCheckpoint();
      await _saveCheckpoint(
        (checkpoint ??
                SyncCheckpointState(
                  syncScope: _personalBackupScope,
                  updatedAt: now,
                ))
            .copyWith(
          lastSuccessfulPushAt: now,
          updatedAt: now,
        ),
      );
    } catch (error) {
      debugPrint('[IkeepDelta] push checkpoint save failed: $error');
    }
  }

  Future<void> _clearPendingSyncForItem(String itemUuid) async {
    try {
      await _pendingSyncDao.deleteByEntity(
        entityType: _personalPendingSyncEntityType,
        entityUuid: itemUuid,
      );
    } catch (error) {
      debugPrint(
        '[IkeepDelta] failed to clear queued personal sync '
        'item=$itemUuid error=$error',
      );
    }
  }

  Future<bool> _remoteTombstoneExists(String itemUuid) async {
    try {
      final snapshot = await _deletedItemsRef.doc(itemUuid).get();
      return snapshot.data() != null;
    } catch (error) {
      debugPrint(
        '[IkeepDelta] tombstone existence check failed '
        'item=$itemUuid error=$error',
      );
      return false;
    }
  }

  Future<void> _clearRemoteItemTombstone(String itemUuid) async {
    try {
      await _deletedItemsRef.doc(itemUuid).delete();
      debugPrint('[IkeepDelta] cleared tombstone item=$itemUuid');
    } on FirebaseException catch (error) {
      if (error.code == 'not-found') {
        return;
      }
      debugPrint(
        '[IkeepDelta] failed to clear tombstone '
        'item=$itemUuid error=$error',
      );
    } catch (error) {
      debugPrint(
        '[IkeepDelta] failed to clear tombstone '
        'item=$itemUuid error=$error',
      );
    }
  }

  Future<void> _applyRemoteTombstonesForFullSyncRecovery() async {
    final snapshot = await _deletedItemsRef.orderBy('deletedAt').get();
    if (snapshot.docs.isEmpty) {
      return;
    }

    debugPrint(
      '[IkeepDelta] full-sync tombstone recovery '
      'count=${snapshot.docs.length}',
    );

    for (final doc in snapshot.docs) {
      final tombstone = _remoteTombstoneFromData(doc.id, doc.data());
      if (tombstone == null) {
        debugPrint(
          '[IkeepDelta] skipped invalid tombstone during full-sync recovery '
          'doc=${doc.id}',
        );
        continue;
      }
      await _applyRemoteItemTombstone(
        tombstone: tombstone,
        source: 'full_sync_recovery',
      );
    }
  }

  Future<_RemoteTombstoneApplyOutcome> _applyRemoteItemTombstone({
    required _RemoteItemTombstone tombstone,
    required String source,
  }) async {
    final localItem = await _itemDao.getItemByUuid(tombstone.itemUuid);
    if (localItem == null) {
      await _clearPendingSyncForItem(tombstone.itemUuid);
      debugPrint(
        '[IkeepDelta] tombstone processed with no local row '
        'item=${tombstone.itemUuid} source=$source '
        'reason=${tombstone.reason}',
      );
      return const _RemoteTombstoneApplyOutcome();
    }

    final shouldApply = await _shouldApplyRemoteTombstone(
      localItem: localItem,
      tombstone: tombstone,
    );
    if (!shouldApply) {
      if (_hasRemoteIdentity(localItem)) {
        await _itemDao.updateItem(
          localItem.copyWith(
            clearCloudId: true,
            clearLastSyncedAt: true,
          ),
        );
      }
      debugPrint(
        '[IkeepDelta] tombstone local-wins '
        'item=${tombstone.itemUuid} source=$source '
        'reason=${tombstone.reason}',
      );
      return const _RemoteTombstoneApplyOutcome(localWins: true);
    }

    if (tombstone.reason == _deleteReasonBackupDisabled) {
      await _itemCloudMediaService.deleteForItem(localItem.uuid);
      await _itemDao.updateItem(
        localItem.copyWith(
          isBackedUp: false,
          clearCloudId: true,
          clearLastSyncedAt: true,
        ),
      );
      await _clearPendingSyncForItem(localItem.uuid);
      debugPrint(
        '[IkeepDelta] tombstone converted item to local-only '
        'item=${tombstone.itemUuid} source=$source',
      );
      return const _RemoteTombstoneApplyOutcome(convertedToLocalOnly: true);
    }

    await _historyDao.deleteHistoryForItem(localItem.uuid);
    await _itemCloudMediaService.deleteForItem(localItem.uuid);
    await _itemDao.deleteItem(localItem.uuid);
    await _clearPendingSyncForItem(localItem.uuid);
    debugPrint(
      '[IkeepDelta] tombstone deleted local item '
      'item=${tombstone.itemUuid} source=$source',
    );
    return const _RemoteTombstoneApplyOutcome(deletedLocally: true);
  }

  Future<bool> _shouldApplyRemoteTombstone({
    required Item localItem,
    required _RemoteItemTombstone tombstone,
  }) async {
    final lastSyncedAt = localItem.lastSyncedAt;
    if (lastSyncedAt == null) {
      return false;
    }
    if (!tombstone.deletedAt.isAfter(lastSyncedAt)) {
      return false;
    }
    if (await _localItemHasUnsyncedChanges(localItem)) {
      return false;
    }
    return true;
  }

  _RemoteItemTombstone? _remoteTombstoneFromData(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final itemUuid = ((data['itemUuid'] as String?) ?? documentId).trim();
    final deletedAt = _parseDateTime(data['deletedAt']);
    if (itemUuid.isEmpty || deletedAt == null) {
      return null;
    }

    return _RemoteItemTombstone(
      itemUuid: itemUuid,
      deletedAt: deletedAt,
      reason: (data['reason'] as String?)?.trim().isNotEmpty == true
          ? (data['reason'] as String).trim()
          : _deleteReasonDeleted,
    );
  }

  Future<bool> _localItemHasUnsyncedChanges(Item item) async {
    final existingImageReferences =
        await _itemCloudMediaService.getImageReferencesForItem(item.uuid);
    final existingInvoiceReference =
        await _itemCloudMediaService.getInvoiceReferenceForItem(item.uuid);
    return _contentChangedSinceLastSync(item) ||
        _locationChangedSinceLastSync(item) ||
        _imageMediaNeedsSync(
          imagePaths: item.imagePaths,
          existingReferences: existingImageReferences,
        ) ||
        _invoiceMediaNeedsSync(
          invoicePath: item.invoicePath,
          existingReference: existingInvoiceReference,
        );
  }

  bool _localItemNeedsDeltaPush(Item item) {
    final lastSyncedAt = item.lastSyncedAt;
    if (lastSyncedAt == null) {
      return true;
    }

    final contentAt = _contentTimestamp(item);
    if (contentAt.isAfter(lastSyncedAt)) {
      return true;
    }

    final locationAt = item.lastMovedAt;
    if (locationAt != null && locationAt.isAfter(lastSyncedAt)) {
      return true;
    }

    return false;
  }

  bool _hasRemoteIdentity(Item item) {
    return (item.cloudId?.trim().isNotEmpty ?? false) ||
        item.lastSyncedAt != null;
  }

  bool _contentChangedSinceLastSync(Item item) {
    final lastSyncedAt = item.lastSyncedAt;
    if (lastSyncedAt == null) {
      return true;
    }
    return _contentTimestamp(item).isAfter(lastSyncedAt);
  }

  bool _locationChangedSinceLastSync(Item item) {
    final lastSyncedAt = item.lastSyncedAt;
    final lastMovedAt = item.lastMovedAt;
    if (lastMovedAt == null) {
      return false;
    }
    if (lastSyncedAt == null) {
      return true;
    }
    return lastMovedAt.isAfter(lastSyncedAt);
  }

  bool _imageMediaNeedsSync({
    required List<String> imagePaths,
    required List<ItemCloudMediaReference> existingReferences,
  }) {
    if (imagePaths.length != existingReferences.length) {
      return true;
    }
    if (imagePaths.isEmpty) {
      return false;
    }

    final referencesBySlot = {
      for (final reference in existingReferences)
        reference.slotIndex: reference,
    };
    for (var index = 0; index < imagePaths.length; index++) {
      if (!referencesBySlot.containsKey(index)) {
        return true;
      }
    }
    return false;
  }

  bool _invoiceMediaNeedsSync({
    required String? invoicePath,
    required ItemCloudMediaReference? existingReference,
  }) {
    final hasInvoice = invoicePath?.trim().isNotEmpty ?? false;
    if (!hasInvoice) {
      return existingReference != null;
    }
    return existingReference == null;
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
        final descriptor = CloudMediaDescriptor.fromJson(
          Map<String, dynamic>.from(entry as Map<dynamic, dynamic>),
        );
        timestamps.add(descriptor.updatedAt);
      }
    }

    final invoiceMedia = remoteData['invoiceMedia'];
    if (invoiceMedia is Map) {
      final descriptor = CloudMediaDescriptor.fromJson(
        Map<String, dynamic>.from(invoiceMedia as Map<dynamic, dynamic>),
      );
      timestamps.add(descriptor.updatedAt);
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

  DateTime _maxDateTime(DateTime a, DateTime b) {
    return a.isAfter(b) ? a : b;
  }

  /// Checks whether the signed-in user has any backed-up items in Firestore.
  ///
  /// Used on fresh installs to decide whether to offer or auto-trigger restore.
  /// Returns false if the user is not signed in.
  @override
  Future<bool> hasRemoteBackup() async {
    final user = _user;
    if (user == null) return false;

    try {
      final snapshot = await _itemsRef.limit(1).get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('FirebaseSyncService.hasRemoteBackup error: $e');
      return false;
    }
  }

  /// Adds a location write to a Firestore [WriteBatch] instead of making an
  /// individual network call.
  void _addLocationToBatch(
    WriteBatch batch,
    LocationModel location,
    User user,
  ) {
    batch.set(
      _locationsRef.doc(location.uuid),
      {
        ...location.toJson(),
        'userId': user.uid,
        'updatedAt': _toIsoString(DateTime.now()),
        'lastSyncedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _upsertLocationsLocally(
    List<LocationModel> locations, {
    required Set<String> existingLocationUuids,
  }) async {
    if (locations.isEmpty) return;

    final orderedLocations = orderLocationsForLocalUpsert(
      locations: locations,
      existingLocationUuids: existingLocationUuids,
    );
    final knownUuids = <String>{...existingLocationUuids};

    for (final location in orderedLocations) {
      if (knownUuids.contains(location.uuid)) {
        await _locationDao.updateLocation(location);
      } else {
        await _locationDao.insertLocation(location);
      }
      knownUuids.add(location.uuid);
    }
  }

  @override
  Future<DateTime?> getLastSyncedAt() async {
    if (_lastSyncedAt != null) return _lastSyncedAt;
    if (_user == null) return null;

    try {
      final checkpoint = await _loadCheckpoint();
      _lastSyncedAt = checkpoint?.latestSuccessfulSyncAt;
      if (_lastSyncedAt != null) {
        return _lastSyncedAt;
      }

      final snapshot = await _userDoc.get();
      _lastSyncedAt = _parseDateTime(snapshot.data()?['lastSyncedAt']);
    } catch (_) {
      return null;
    }
    return _lastSyncedAt;
  }

  Future<void> _ensureUserDocument(User user) async {
    await _userDoc.set({
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'photoUrl': user.photoURL,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Reconstructs an [Item] from its Firestore document without downloading
  /// media during restore.
  ///
  /// Phase 4 keeps the legacy `imagePaths` / `invoicePath` values in SQLite so
  /// older UI flows keep working, but stores descriptor/storage metadata in a
  /// sidecar SQLite registry for lazy cache-backed access later.
  Item _itemFromFirestore(Map<String, dynamic> data) {
    final itemUuid = (data['uuid'] as String?) ?? '';
    final restoredImagePaths =
        _itemCloudMediaService.restoredImagePathsFromCloudData(data);
    final restoredInvoicePath =
        _itemCloudMediaService.restoredInvoicePathFromCloudData(data);

    debugPrint(
      '[IkeepRestore] metadata-first restore for $itemUuid '
      'images=${restoredImagePaths.length} '
      'hasInvoice=${restoredInvoicePath?.isNotEmpty == true}',
    );

    return Item(
      uuid: itemUuid,
      name: (data['name'] as String?) ?? 'Untitled item',
      locationUuid: data['locationUuid'] as String?,
      // Hierarchical location FKs — present in new backups, null in legacy
      // ones (the migration service fills them in on first startup).
      areaUuid: data['areaUuid'] as String?,
      roomUuid: data['roomUuid'] as String?,
      zoneUuid: data['zoneUuid'] as String?,
      imagePaths: restoredImagePaths,
      tags: List<String>.from((data['tags'] as List?) ?? const []),
      savedAt: _parseDateTime(data['savedAt']) ??
          _parseDateTime(data['createdAt']) ??
          DateTime.now(),
      updatedAt: _parseDateTime(data['updatedAt']),
      lastUpdatedAt: _parseDateTime(data['lastUpdatedAt']) ??
          _parseDateTime(data['updatedAt']),
      lastMovedAt: _parseDateTime(data['lastMovedAt']),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      expiryDate: _parseDateTime(data['expiryDate']),
      warrantyEndDate: _parseDateTime(data['warrantyEndDate']),
      isArchived: data['isArchived'] as bool? ?? false,
      notes: data['notes'] as String?,
      invoicePath: restoredInvoicePath,
      invoiceFileName: data['invoiceFileName'] as String?,
      invoiceFileSizeBytes:
          (data['invoiceUploadedFileSizeBytes'] as num?)?.toInt() ??
              (data['invoiceFileSizeBytes'] as num?)?.toInt(),
      cloudId: data['cloudId'] as String? ?? data['uuid'] as String?,
      lastSyncedAt: _parseDateTime(data['lastSyncedAt']),
      isBackedUp: data['isBackedUp'] as bool? ?? true,
      isLent: data['isLent'] as bool? ?? false,
      lentTo: data['lentTo'] as String?,
      lentOn: _parseDateTime(data['lentOn']),
      expectedReturnDate: _parseDateTime(data['expectedReturnDate']),
      seasonCategory: (data['seasonCategory'] as String?) ?? 'all_year',
      lentReminderAfterDays: data['lentReminderAfterDays'] as int?,
      isAvailableForLending: data['isAvailableForLending'] as bool? ?? false,
      visibility: ItemVisibility.fromString(data['visibility'] as String?),
      householdId: data['householdId'] as String?,
      sharedWithMemberUuids: List<String>.from(
        (data['sharedWithMemberUuids'] as List?) ?? const [],
      ),
    );
  }

  LocationModel _locationFromFirestore(Map<String, dynamic> data) {
    return LocationModel(
      uuid: (data['uuid'] as String?) ?? '',
      name: (data['name'] as String?) ?? 'Untitled location',
      type: LocationType.fromStorage(
        data['type'] as String?,
        parentUuid: data['parentUuid'] as String?,
      ),
      fullPath: data['fullPath'] as String?,
      parentUuid: data['parentUuid'] as String?,
      iconName: (data['iconName'] as String?) ?? 'folder',
      usageCount: data['usageCount'] as int? ?? 0,
      createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String _toIsoString(DateTime? value) {
    return (value ?? DateTime.now()).toIso8601String();
  }

  bool _isLocationInSync(
    LocationModel local,
    Map<String, dynamic> remoteData,
  ) {
    return local.uuid == ((remoteData['uuid'] as String?) ?? local.uuid) &&
        local.name == (remoteData['name'] as String? ?? '') &&
        local.type.value ==
            LocationType.fromStorage(
              remoteData['type'] as String?,
              parentUuid: remoteData['parentUuid'] as String?,
            ).value &&
        local.fullPath == remoteData['fullPath'] as String? &&
        local.parentUuid == remoteData['parentUuid'] as String? &&
        local.iconName == ((remoteData['iconName'] as String?) ?? 'folder');
  }

  bool _isItemInSync({
    required Item item,
    required DateTime localUpdatedAt,
    required DateTime? remoteUpdatedAt,
  }) {
    final lastSyncedAt = item.lastSyncedAt;
    if (lastSyncedAt == null || remoteUpdatedAt == null) {
      return false;
    }

    final localUnchangedSinceLastSync = !localUpdatedAt.isAfter(lastSyncedAt);
    final remoteUnchangedSinceLastSync = !remoteUpdatedAt.isAfter(lastSyncedAt);
    return localUnchangedSinceLastSync && remoteUnchangedSinceLastSync;
  }

  Future<void> _evaluateCloudQuotaForItem(Item item) async {
    final evaluation = await _cloudQuotaService.evaluatePersonalItemWrite(item);
    if (!evaluation.allowedNow) {
      throw SyncException(evaluation.message);
    }
  }

  bool _isMissingRemoteResource(dynamic error) {
    final str = error.toString().toLowerCase();
    if (str.contains('object-not-found') ||
        str.contains('no object exists') ||
        str.contains('not-found')) {
      return true;
    }
    if (error is FirebaseException) {
      final message = error.message?.toLowerCase() ?? '';
      return error.code == 'not-found' ||
          error.code == 'object-not-found' ||
          message.contains('no object exists at the desired reference');
    }
    return false;
  }

  /// Returns the history subcollection reference for a given item.
  /// Path: users/{uid}/items/{itemUuid}/history
  CollectionReference<Map<String, dynamic>> _historyRef(String itemUuid) =>
      _itemsRef.doc(itemUuid).collection(_historyCollection);

  /// Uploads all local history records for an item to its Firestore
  /// subcollection. Uses batched writes for efficiency. Existing records
  /// are merged so re-syncing the same item is idempotent.
  Future<void> _syncItemHistory(String itemUuid) async {
    final localHistory = await _historyDao.getHistoryForItem(itemUuid);
    if (localHistory.isEmpty) {
      debugPrint('[IkeepSync] History sync: no local history for $itemUuid');
      return;
    }

    debugPrint(
      '[IkeepSync] History sync: uploading ${localHistory.length} '
      'record(s) for item $itemUuid',
    );

    final ref = _historyRef(itemUuid);
    final batch = _firestore.batch();
    for (final entry in localHistory) {
      batch.set(
        ref.doc(entry.uuid),
        entry.toJson(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();

    debugPrint(
      '[IkeepSync] History sync: uploaded ${localHistory.length} '
      'record(s) for item $itemUuid',
    );
  }

  /// Downloads all history records for an item from Firestore and upserts
  /// them into local SQLite. Uses the history UUID as a dedup key so
  /// duplicate records are safely skipped.
  Future<void> _restoreItemHistory(String itemUuid) async {
    final snapshot = await _historyRef(itemUuid).get();
    if (snapshot.docs.isEmpty) {
      debugPrint(
          '[IkeepSync] History restore: no remote history for $itemUuid');
      return;
    }

    debugPrint(
      '[IkeepSync] History restore: merging ${snapshot.docs.length} '
      'record(s) for item $itemUuid',
    );

    var merged = 0;
    for (final doc in snapshot.docs) {
      try {
        final history = ItemLocationHistory.fromJson(doc.data());
        await _historyDao.upsertHistory(history);
        merged++;
      } catch (e) {
        debugPrint(
          '[IkeepSync] History restore: failed to merge ${doc.id} '
          'for item $itemUuid: $e',
        );
      }
    }

    debugPrint(
      '[IkeepSync] History restore: merged $merged/${snapshot.docs.length} '
      'record(s) for item $itemUuid',
    );
  }

  /// Deletes the entire history subcollection for an item from Firestore.
  Future<void> _deleteRemoteItemHistory(String itemUuid) async {
    final snapshot = await _historyRef(itemUuid).get();
    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    debugPrint(
      '[IkeepSync] Deleted ${snapshot.docs.length} remote history '
      'record(s) for item $itemUuid',
    );
  }

  Future<void> _recordUploadObservation({
    required String source,
    ImageUploadResult? imageResult,
    StoredInvoiceFile? uploadedInvoice,
  }) async {
    final estimatedBytes = _estimatedUploadBytesForResult(
      imageResult: imageResult,
      uploadedInvoice: uploadedInvoice,
    );
    if (estimatedBytes <= 0) {
      return;
    }

    try {
      await _cloudObservationService.recordUpload(
        estimatedBytes: estimatedBytes,
        source: source,
      );
    } catch (error) {
      debugPrint(
        '[IkeepObserve] upload observation failed '
        'source=$source error=$error',
      );
    }
  }

  int _estimatedUploadBytesForResult({
    ImageUploadResult? imageResult,
    StoredInvoiceFile? uploadedInvoice,
  }) {
    var totalBytes = 0;

    if (imageResult != null) {
      for (final descriptor in imageResult.mediaDescriptors) {
        totalBytes += descriptor.byteSize;
        if ((descriptor.thumbnailPath?.trim().isNotEmpty ?? false)) {
          totalBytes += targetThumbnailBytes;
        }
      }
    }

    totalBytes += uploadedInvoice?.sizeBytes ??
        uploadedInvoice?.mediaDescriptor?.byteSize ??
        uploadedInvoice?.originalFileSizeBytes ??
        0;
    return totalBytes;
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
        '[IkeepObserve] sync observation failed source=$source error=$error',
      );
    }
  }
}

class _DeltaPullOutcome {
  const _DeltaPullOutcome({
    required this.success,
    required this.importedCount,
    this.deletedCount = 0,
    this.convertedCount = 0,
  });

  final bool success;
  final int importedCount;
  final int deletedCount;
  final int convertedCount;
}

class _DeltaPushOutcome {
  const _DeltaPushOutcome({
    required this.success,
    required this.syncedItems,
    required this.deletedItems,
    required this.skippedItems,
    required this.failedItems,
    required this.itemOutcomes,
  });

  final bool success;
  final int syncedItems;
  final int deletedItems;
  final int skippedItems;
  final int failedItems;
  final List<ItemSyncOutcome> itemOutcomes;
}

class _DeltaMergeOutcome {
  const _DeltaMergeOutcome({
    required this.mergedItem,
    required this.replaceSidecarFromRemote,
    required this.restoreHistoryFromRemote,
  });

  final Item mergedItem;
  final bool replaceSidecarFromRemote;
  final bool restoreHistoryFromRemote;
}

class _QueuedDeleteRequest {
  const _QueuedDeleteRequest({
    required this.itemUuid,
    required this.itemName,
    required this.reason,
  });

  final String itemUuid;
  final String itemName;
  final String reason;
}

class _RemoteItemTombstone {
  const _RemoteItemTombstone({
    required this.itemUuid,
    required this.deletedAt,
    required this.reason,
  });

  final String itemUuid;
  final DateTime deletedAt;
  final String reason;

  Map<String, dynamic> toJson() {
    final deletedAtIso = deletedAt.toIso8601String();
    return {
      'itemUuid': itemUuid,
      'deletedAt': deletedAtIso,
      'updatedAt': deletedAtIso,
      'syncScope': 'personal_backup',
      'reason': reason,
    };
  }
}

class _RemoteDeltaEvent {
  const _RemoteDeltaEvent.item({
    required this.itemUuid,
    required this.changedAt,
    required this.data,
  }) : tombstone = null;

  _RemoteDeltaEvent.tombstone({
    required _RemoteItemTombstone tombstone,
  })  : itemUuid = tombstone.itemUuid,
        changedAt = tombstone.deletedAt,
        data = null,
        tombstone = tombstone;

  final String itemUuid;
  final DateTime changedAt;
  final Map<String, dynamic>? data;
  final _RemoteItemTombstone? tombstone;
}

class _RemoteTombstoneApplyOutcome {
  const _RemoteTombstoneApplyOutcome({
    this.deletedLocally = false,
    this.convertedToLocalOnly = false,
    this.localWins = false,
  });

  final bool deletedLocally;
  final bool convertedToLocalOnly;
  final bool localWins;
}

class _DeltaSyncFallbackException implements Exception {
  const _DeltaSyncFallbackException(this.reason);

  final String reason;

  @override
  String toString() => 'Delta sync fallback: $reason';
}
