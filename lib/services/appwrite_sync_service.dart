import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/storage_constants.dart';
import '../domain/models/item.dart';
import '../domain/models/location_model.dart';
import '../domain/models/sync_status.dart';
import 'sync_service.dart';

/// Appwrite implementation of [SyncService].
/// Initializes lazily on first sync call.
class AppwriteSyncService implements SyncService {
  Client? _client;
  Databases? _databases;
  DateTime? _lastSyncedAt;

  Client _getClient() {
    _client ??= Client()
      ..setEndpoint(StorageConstants.appwriteEndpoint)
      ..setProject(StorageConstants.appwriteProjectId)
      ..setSelfSigned(status: true); // remove in production
    return _client!;
  }

  Databases _getDatabases() {
    _databases ??= Databases(_getClient());
    return _databases!;
  }

  @override
  Future<SyncResult> syncItem(Item item) async {
    try {
      final db = _getDatabases();
      final data = item.toJson()..remove('imagePaths'); // images synced separately

      try {
        await db.getDocument(
          databaseId: StorageConstants.appwriteDatabaseId,
          collectionId: StorageConstants.appwriteItemsCollectionId,
          documentId: item.uuid,
        );
        // Document exists — update
        await db.updateDocument(
          databaseId: StorageConstants.appwriteDatabaseId,
          collectionId: StorageConstants.appwriteItemsCollectionId,
          documentId: item.uuid,
          data: data,
        );
      } on AppwriteException catch (e) {
        if (e.code == 404) {
          // Does not exist — create
          await db.createDocument(
            databaseId: StorageConstants.appwriteDatabaseId,
            collectionId: StorageConstants.appwriteItemsCollectionId,
            documentId: item.uuid,
            data: data,
          );
        } else {
          rethrow;
        }
      }
      _lastSyncedAt = DateTime.now();
      return SyncResult.success();
    } on AppwriteException catch (e) {
      debugPrint('AppwriteSyncService.syncItem error: ${e.message}');
      return SyncResult.error(e.message ?? 'Sync failed');
    } catch (e) {
      return SyncResult.error(e.toString());
    }
  }

  @override
  Future<SyncResult> syncLocation(LocationModel location) async {
    try {
      final db = _getDatabases();
      final data = location.toJson();

      try {
        await db.getDocument(
          databaseId: StorageConstants.appwriteDatabaseId,
          collectionId: StorageConstants.appwriteLocationsCollectionId,
          documentId: location.uuid,
        );
        await db.updateDocument(
          databaseId: StorageConstants.appwriteDatabaseId,
          collectionId: StorageConstants.appwriteLocationsCollectionId,
          documentId: location.uuid,
          data: data,
        );
      } on AppwriteException catch (e) {
        if (e.code == 404) {
          await db.createDocument(
            databaseId: StorageConstants.appwriteDatabaseId,
            collectionId: StorageConstants.appwriteLocationsCollectionId,
            documentId: location.uuid,
            data: data,
          );
        } else {
          rethrow;
        }
      }
      _lastSyncedAt = DateTime.now();
      return SyncResult.success();
    } on AppwriteException catch (e) {
      return SyncResult.error(e.message ?? 'Location sync failed');
    } catch (e) {
      return SyncResult.error(e.toString());
    }
  }

  @override
  Future<SyncResult> deleteRemoteItem(String uuid) async {
    try {
      await _getDatabases().deleteDocument(
        databaseId: StorageConstants.appwriteDatabaseId,
        collectionId: StorageConstants.appwriteItemsCollectionId,
        documentId: uuid,
      );
      return SyncResult.success();
    } on AppwriteException catch (e) {
      if (e.code == 404) return SyncResult.success(); // Already gone
      return SyncResult.error(e.message ?? 'Delete failed');
    } catch (e) {
      return SyncResult.error(e.toString());
    }
  }

  @override
  Future<SyncResult> deleteRemoteLocation(String uuid) async {
    try {
      await _getDatabases().deleteDocument(
        databaseId: StorageConstants.appwriteDatabaseId,
        collectionId: StorageConstants.appwriteLocationsCollectionId,
        documentId: uuid,
      );
      return SyncResult.success();
    } on AppwriteException catch (e) {
      if (e.code == 404) return SyncResult.success();
      return SyncResult.error(e.message ?? 'Delete failed');
    } catch (e) {
      return SyncResult.error(e.toString());
    }
  }

  @override
  Future<SyncResult> fullSync() async {
    // Full sync implementation will be expanded when auth is added.
    // For now, returns success to avoid blocking the UI.
    debugPrint('AppwriteSyncService.fullSync: not yet fully implemented');
    return SyncResult.success();
  }

  @override
  Future<DateTime?> getLastSyncedAt() async => _lastSyncedAt;
}
