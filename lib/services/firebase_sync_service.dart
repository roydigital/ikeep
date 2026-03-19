import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/database/item_dao.dart';
import '../data/database/location_dao.dart';
import '../domain/models/item.dart';
import '../domain/models/item_visibility.dart';
import '../domain/models/location_model.dart';
import '../domain/models/sync_status.dart';
import 'firebase_image_upload_service.dart';
import 'sync_service.dart';

class FirebaseSyncService implements SyncService {
  FirebaseSyncService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required ItemDao itemDao,
    required LocationDao locationDao,
    required FirebaseImageUploadService imageUploadService,
  })  : _auth = auth,
        _firestore = firestore,
        _itemDao = itemDao,
        _locationDao = locationDao,
        _imageUploadService = imageUploadService;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final ItemDao _itemDao;
  final LocationDao _locationDao;
  final FirebaseImageUploadService _imageUploadService;

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
    final user = _user;
    if (user == null) {
      return const SyncResult.error('Sign in to sync items to Firebase');
    }

    try {
      final now = FieldValue.serverTimestamp();
      final uploadedImageUrls = await _imageUploadService.uploadItemImages(
        userId: user.uid,
        itemUuid: item.uuid,
        imagePaths: item.imagePaths,
      );

      await _ensureUserDocument(user);
      await _itemsRef.doc(item.uuid).set({
        ...item.copyWith(imagePaths: uploadedImageUrls).toJson(),
        'userId': user.uid,
        'updatedAt': _toIsoString(item.updatedAt ?? DateTime.now()),
        'createdAt': _toIsoString(item.savedAt),
        'lastSyncedAt': now,
      }, SetOptions(merge: true));
      _lastSyncedAt = DateTime.now();
      return SyncResult.success();
    } catch (e) {
      debugPrint('FirebaseSyncService.syncItem error: $e');
      return SyncResult.error(e.toString());
    }
  }

  @override
  Future<SyncResult> syncLocation(LocationModel location) async {
    final user = _user;
    if (user == null) {
      return const SyncResult.error('Sign in to sync locations to Firebase');
    }

    try {
      await _ensureUserDocument(user);
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
      await _imageUploadService.deleteItemImages(
        userId: _user!.uid,
        itemUuid: uuid,
      );
      await _itemsRef.doc(uuid).delete();
      _lastSyncedAt = DateTime.now();
      return SyncResult.success();
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') return SyncResult.success();
      return SyncResult.error(e.message ?? 'Failed to delete remote item');
    } catch (e) {
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

  @override
  Future<SyncResult> fullSync() async {
    final user = _user;
    if (user == null) {
      return const SyncResult.error(
          'Please sign in with Google before syncing');
    }

    try {
      await _ensureUserDocument(user);

      final localLocations = await _locationDao.getAllLocations();
      final localItems = await _itemDao.getAllItems();
      final remoteLocationsSnapshot = await _locationsRef.get();
      final remoteItemsSnapshot = await _itemsRef.get();

      final remoteLocations = {
        for (final doc in remoteLocationsSnapshot.docs) doc.id: doc.data(),
      };
      final remoteItems = {
        for (final doc in remoteItemsSnapshot.docs) doc.id: doc.data(),
      };

      for (final location in localLocations) {
        final remoteData = remoteLocations[location.uuid];
        if (remoteData == null) {
          await syncLocation(location);
          continue;
        }

        final remoteUpdatedAt = _parseDateTime(remoteData['updatedAt']);
        final localUpdatedAt = location.createdAt;
        if (remoteUpdatedAt != null &&
            remoteUpdatedAt.isAfter(localUpdatedAt)) {
          await _locationDao.insertLocation(_locationFromFirestore(remoteData));
        } else {
          await syncLocation(location);
        }
      }

      for (final remoteEntry in remoteLocations.entries) {
        final existsLocally =
            localLocations.any((loc) => loc.uuid == remoteEntry.key);
        if (!existsLocally) {
          await _locationDao
              .insertLocation(_locationFromFirestore(remoteEntry.value));
        }
      }

      for (final item in localItems) {
        final remoteData = remoteItems[item.uuid];
        final localUpdatedAt = item.updatedAt ?? item.savedAt;
        if (remoteData == null) {
          await syncItem(item);
          continue;
        }

        final remoteUpdatedAt = _parseDateTime(remoteData['updatedAt']) ??
            _parseDateTime(remoteData['savedAt']);
        if (remoteUpdatedAt != null &&
            remoteUpdatedAt.isAfter(localUpdatedAt)) {
          await _itemDao.insertItem(_itemFromFirestore(remoteData));
        } else {
          await syncItem(item);
        }
      }

      for (final remoteEntry in remoteItems.entries) {
        final existsLocally =
            localItems.any((item) => item.uuid == remoteEntry.key);
        if (!existsLocally) {
          await _itemDao.insertItem(_itemFromFirestore(remoteEntry.value));
        }
      }

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

  Item _itemFromFirestore(Map<String, dynamic> data) {
    return Item(
      uuid: (data['uuid'] as String?) ?? '',
      name: (data['name'] as String?) ?? 'Untitled item',
      locationUuid: data['locationUuid'] as String?,
      imagePaths: List<String>.from((data['imagePaths'] as List?) ?? const []),
      tags: List<String>.from((data['tags'] as List?) ?? const []),
      savedAt: _parseDateTime(data['savedAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(data['updatedAt']),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      expiryDate: _parseDateTime(data['expiryDate']),
      isArchived: data['isArchived'] as bool? ?? false,
      notes: data['notes'] as String?,
      cloudId: data['cloudId'] as String? ?? data['uuid'] as String?,
      lastSyncedAt: _parseDateTime(data['lastSyncedAt']),
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
}
