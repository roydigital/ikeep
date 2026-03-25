import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/feature_limits.dart';
import '../core/errors/app_exception.dart';
import '../data/database/item_dao.dart';
import '../data/database/location_dao.dart';
import '../domain/models/item.dart';
import '../domain/models/item_visibility.dart';
import '../domain/models/location_model.dart';
import '../domain/models/sync_status.dart';
import 'firebase_image_upload_service.dart';
import 'firebase_invoice_storage_service.dart';
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
    required FirebaseImageUploadService imageUploadService,
    required FirebaseInvoiceStorageService invoiceStorageService,
  })  : _auth = auth,
        _firestore = firestore,
        _itemDao = itemDao,
        _locationDao = locationDao,
        _imageUploadService = imageUploadService,
        _invoiceStorageService = invoiceStorageService;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final ItemDao _itemDao;
  final LocationDao _locationDao;
  final FirebaseImageUploadService _imageUploadService;
  final FirebaseInvoiceStorageService _invoiceStorageService;

  DateTime? _lastSyncedAt;

  static const _usersCollection = 'users';
  static const _itemsCollection = 'items';
  static const _locationsCollection = 'locations';

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

  CollectionReference<Map<String, dynamic>> get _locationsRef =>
      _userDoc.collection(_locationsCollection);

  @override
  Future<SyncResult> syncItem(Item item) async {
    return _syncItemInternal(item, ensureUserDocument: true);
  }

  Future<SyncResult> _syncItemInternal(
    Item item, {
    required bool ensureUserDocument,
  }) async {
    final user = _user;
    if (user == null) {
      return const SyncResult.error('Sign in to sync items to Firebase');
    }

    if (!item.isBackedUp) {
      return SyncResult.success();
    }

    try {
      await _ensureCloudQuotaForItem(item);

      final now = FieldValue.serverTimestamp();
      final syncedAt = DateTime.now();

      // Run image uploads and user-doc check in parallel — they are
      // independent network calls.
      final results = await Future.wait<Object?>([
        _imageUploadService.uploadItemImages(
          userId: user.uid,
          itemUuid: item.uuid,
          imagePaths: item.imagePaths,
        ),
        _invoiceStorageService.uploadItemInvoice(
          userId: user.uid,
          itemUuid: item.uuid,
          invoicePath: item.invoicePath,
          invoiceFileName: item.invoiceFileName,
          invoiceFileSizeBytes: item.invoiceFileSizeBytes,
        ),
        if (ensureUserDocument) _ensureUserDocument(user),
      ]);
      final uploadedImageUrls = results[0] as List<String>;
      final uploadedInvoice = results[1] as StoredInvoiceFile?;

      await _itemsRef.doc(item.uuid).set({
        ...item
            .copyWith(
              imagePaths: uploadedImageUrls,
              invoicePath: uploadedInvoice?.path,
              invoiceFileName: uploadedInvoice?.fileName,
              invoiceFileSizeBytes: uploadedInvoice?.sizeBytes,
              clearInvoicePath: uploadedInvoice == null,
              clearInvoiceFileName: uploadedInvoice == null,
              clearInvoiceFileSizeBytes: uploadedInvoice == null,
              cloudId: item.cloudId ?? item.uuid,
              lastSyncedAt: syncedAt,
              isBackedUp: true,
            )
            .toJson(),
        'userId': user.uid,
        'updatedAt': _toIsoString(item.updatedAt ?? DateTime.now()),
        'createdAt': _toIsoString(item.savedAt),
        'lastSyncedAt': now,
      }, SetOptions(merge: true));
      await _itemDao.updateItem(
        item.copyWith(
          cloudId: item.cloudId ?? item.uuid,
          lastSyncedAt: syncedAt,
          isBackedUp: true,
        ),
      );
      _lastSyncedAt = DateTime.now();
      return SyncResult.success();
    } on SyncException catch (e) {
      debugPrint('FirebaseSyncService.syncItem quota error: $e');
      return SyncResult.error(e.message);
    } catch (e) {
      debugPrint('FirebaseSyncService.syncItem error: $e');
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
      _lastSyncedAt = DateTime.now();
      return SyncResult.success();
    } catch (e) {
      debugPrint('FirebaseSyncService.syncLocation error: $e');
      return SyncResult.error(e.toString());
    }
  }

  @override
  Future<SyncResult> deleteRemoteItem(String uuid) async {
    if (_user == null) {
      return const SyncResult.error('Sign in to sync items to Firebase');
    }

    try {
      await Future.wait([
        _imageUploadService.deleteItemImages(
          userId: _user!.uid,
          itemUuid: uuid,
        ),
        _invoiceStorageService.deleteItemInvoice(
          userId: _user!.uid,
          itemUuid: uuid,
        ),
      ]);
      await _itemsRef.doc(uuid).delete();
      _lastSyncedAt = DateTime.now();
      return SyncResult.success();
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
  Future<SyncResult> fullSync() async {
    final user = _user;
    if (user == null) {
      return const SyncResult.error(
          'Please sign in with Google before syncing');
    }

    try {
      // Kick off all independent fetches in parallel.
      final results = await Future.wait([
        _ensureUserDocument(user), // 0
        _locationDao.recalculateUsageCounts(), // 1
        _locationDao.getAllLocations(), // 2
        _itemDao.getAllItems(), // 3
        _locationsRef.get(), // 4
        _itemsRef.get(), // 5
      ]);

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

      // Commit Firestore batch and local inserts in parallel.
      await Future.wait([
        if (locationBatchCount > 0) locationBatch.commit(),
        _upsertLocationsLocally(
          localLocationUpserts,
          existingLocationUuids: existingLocalLocationUuids,
        ),
      ]);

      // ── Items: process in parallel batches of _syncBatchSize ──
      // Separate items into categories to avoid unnecessary sequential waits.
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

      // Import remote-only items locally (pure SQLite, fast).
      if (itemsToImportLocally.isNotEmpty) {
        await Future.wait(
          itemsToImportLocally.map((data) async {
            await _itemDao.insertItem(await _itemFromFirestore(data));
          }),
        );
      }

      // Delete un-backed-up items from remote (parallel).
      if (itemsToDelete.isNotEmpty) {
        await Future.wait(
          itemsToDelete.map((uuid) => deleteRemoteItem(uuid)),
        );
      }

      // Upload items in controlled parallel batches to avoid flooding the
      // network. Each _syncItemInternal already parallelizes its own image
      // uploads, so _syncBatchSize keeps total concurrency reasonable.
      for (var i = 0; i < itemsToUpload.length; i += _syncBatchSize) {
        final batch = itemsToUpload.skip(i).take(_syncBatchSize);
        await Future.wait(
          batch.map(
              (item) => _syncItemInternal(item, ensureUserDocument: false)),
        );
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

      return SyncResult.success();
    } catch (e) {
      debugPrint('FirebaseSyncService.fullSync error: $e');
      return SyncResult.error(e.toString());
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

  Future<Item> _itemFromFirestore(Map<String, dynamic> data) async {
    final itemUuid = (data['uuid'] as String?) ?? '';
    final rawImagePaths =
        List<String>.from((data['imagePaths'] as List?) ?? const []);
    final remoteUserId = (data['userId'] as String?)?.trim();
    final storageUserId = remoteUserId != null && remoteUserId.isNotEmpty
        ? remoteUserId
        : _user?.uid;
    final resolvedImagePaths =
        storageUserId == null || storageUserId.isEmpty || itemUuid.isEmpty
            ? rawImagePaths
            : await _imageUploadService.resolveCloudImageUrls(
                userId: storageUserId,
                itemUuid: itemUuid,
                imagePaths: rawImagePaths,
              );
    final resolvedInvoice =
        storageUserId == null || storageUserId.isEmpty || itemUuid.isEmpty
            ? ((data['invoicePath'] as String?)?.trim().isNotEmpty ?? false)
                ? StoredInvoiceFile(
                    path: (data['invoicePath'] as String).trim(),
                    fileName: ((data['invoiceFileName'] as String?)
                                ?.trim()
                                .isNotEmpty ??
                            false)
                        ? (data['invoiceFileName'] as String).trim()
                        : 'invoice',
                    sizeBytes: (data['invoiceFileSizeBytes'] as num?)?.toInt(),
                  )
                : null
            : await _invoiceStorageService.resolveCloudInvoice(
                userId: storageUserId,
                itemUuid: itemUuid,
                invoicePath: data['invoicePath'] as String?,
                invoiceFileName: data['invoiceFileName'] as String?,
                invoiceFileSizeBytes:
                    (data['invoiceFileSizeBytes'] as num?)?.toInt(),
              );

    return Item(
      uuid: itemUuid,
      name: (data['name'] as String?) ?? 'Untitled item',
      locationUuid: data['locationUuid'] as String?,
      imagePaths: resolvedImagePaths,
      tags: List<String>.from((data['tags'] as List?) ?? const []),
      savedAt: _parseDateTime(data['savedAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(data['updatedAt']),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      expiryDate: _parseDateTime(data['expiryDate']),
      warrantyEndDate: _parseDateTime(data['warrantyEndDate']),
      isArchived: data['isArchived'] as bool? ?? false,
      notes: data['notes'] as String?,
      invoicePath: resolvedInvoice?.path,
      invoiceFileName: resolvedInvoice?.fileName,
      invoiceFileSizeBytes: resolvedInvoice?.sizeBytes,
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

  Future<void> _ensureCloudQuotaForItem(Item item) async {
    final isExistingCloudItem =
        (item.cloudId?.trim().isNotEmpty ?? false) || item.lastSyncedAt != null;
    if (isExistingCloudItem) return;

    final backedUpItemCount = await _itemDao.countBackedUpItems();
    if (backedUpItemCount > cloudBackupLimit) {
      throw SyncException(
        cloudBackupQuotaExceededError(),
      );
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
}
