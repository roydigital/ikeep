import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/storage_constants.dart';
import '../core/utils/path_utils.dart';
import 'image_optimizer_service.dart';

class FirebaseImageUploadService {
  FirebaseImageUploadService({
    required FirebaseStorage storage,
    required ImageOptimizerService optimizer,
  })  : _storage = storage,
        _optimizer = optimizer;

  final FirebaseStorage _storage;
  final ImageOptimizerService _optimizer;
  final Map<String, _CachedUpload> _uploadCache = {};
  static const String _sourceModifiedMsKey = 'sourceModifiedMs';
  static const String _sourceBytesKey = 'sourceBytes';

  Future<List<String>> uploadItemImages({
    required String userId,
    required String itemUuid,
    required List<String> imagePaths,
  }) async {
    if (imagePaths.isEmpty) {
      await deleteItemImages(userId: userId, itemUuid: itemUuid);
      return const [];
    }

    // Process each image slot in parallel using Future.wait.
    final futures = <Future<_UploadSlotResult>>[];
    for (var index = 0; index < imagePaths.length; index++) {
      futures.add(_uploadSingleImage(
        userId: userId,
        itemUuid: itemUuid,
        index: index,
        path: imagePaths[index],
      ));
    }
    final results = await Future.wait(futures);

    final downloadUrls = <String>[];
    final keepStoragePaths = <String>{};
    for (final result in results) {
      if (result.downloadUrl != null) {
        downloadUrls.add(result.downloadUrl!);
      }
      if (result.storagePath != null) {
        keepStoragePaths.add(result.storagePath!);
      }
    }

    // Prune stale images in the background — no need to block the caller.
    _pruneUnexpectedImages(
      userId: userId,
      itemUuid: itemUuid,
      keepStoragePaths: keepStoragePaths,
    );

    return downloadUrls;
  }

  /// Handles a single image slot: cache check → reuse check → optimize →
  /// upload. Fully self-contained so multiple slots run concurrently.
  Future<_UploadSlotResult> _uploadSingleImage({
    required String userId,
    required String itemUuid,
    required int index,
    required String path,
  }) async {
    if (path.trim().isEmpty) return const _UploadSlotResult();

    // Already a remote URL — nothing to upload.
    if (PathUtils.isRemotePath(path)) {
      final fullPath = _tryResolveStoragePath(path);
      return _UploadSlotResult(downloadUrl: path, storagePath: fullPath);
    }

    final storagePath = _storagePathFor(
      userId: userId,
      itemUuid: itemUuid,
      index: index,
      extension: _optimizer.preferredUploadExtension,
    );
    final ref = _storage.ref().child(storagePath);
    final localFileState = await _localFileState(path);
    final cacheKey = localFileState == null
        ? null
        : _cacheKeyFor(
            localPath: path,
            storagePath: storagePath,
            modifiedMs: localFileState.modifiedMs,
            byteSize: localFileState.byteSize,
          );

    // 1. In-memory cache hit.
    final cached = cacheKey == null ? null : _uploadCache[cacheKey];
    if (cached != null) {
      return _UploadSlotResult(
        downloadUrl: cached.downloadUrl,
        storagePath: cached.fullPath,
      );
    }

    // 2. Reuse existing upload on Firebase Storage.
    final reused = localFileState == null
        ? null
        : await _tryReuseExistingUpload(
            ref: ref,
            cacheKey: cacheKey,
            localFileState: localFileState,
          );
    if (reused != null) {
      return _UploadSlotResult(
        downloadUrl: reused.downloadUrl,
        storagePath: reused.fullPath,
      );
    }

    // 3. Optimize and upload.
    final optimized = await _optimizer.optimizeForUpload(path);
    try {
      await ref.putFile(
        optimized.file,
        SettableMetadata(
          contentType: optimized.contentType,
          cacheControl: 'public,max-age=31536000',
          customMetadata: {
            'optimized': 'true',
            'optimizedBytes': optimized.byteSize.toString(),
            if (localFileState != null) ...{
              _sourceModifiedMsKey: localFileState.modifiedMs.toString(),
              _sourceBytesKey: localFileState.byteSize.toString(),
            },
          },
        ),
      );

      final downloadUrl = await ref.getDownloadURL();
      if (cacheKey != null) {
        _uploadCache[cacheKey] = _CachedUpload(
          fullPath: ref.fullPath,
          downloadUrl: downloadUrl,
        );
      }
      return _UploadSlotResult(
        downloadUrl: downloadUrl,
        storagePath: ref.fullPath,
      );
    } catch (e) {
      if (!_isMissingObjectError(e)) rethrow;
      debugPrint(
        'FirebaseImageUploadService: skipped image $index – $e',
      );
      return const _UploadSlotResult();
    } finally {
      await _safeDelete(optimized.file);
    }
  }

  Future<void> deleteItemImages({
    required String userId,
    required String itemUuid,
  }) async {
    try {
      final folder = _storage.ref().child(_itemFolder(userId, itemUuid));
      final list = await folder.listAll();
      // Delete all images in parallel.
      await Future.wait(list.items.map((ref) async {
        try {
          await ref.delete();
        } catch (e) {
          if (!_isMissingObjectError(e)) rethrow;
        }
      }));
    } catch (e) {
      if (!_isMissingObjectError(e)) rethrow;
    }

    _uploadCache.removeWhere(
      (_, cached) => cached.fullPath.startsWith(_itemFolder(userId, itemUuid)),
    );
  }

  Future<void> _pruneUnexpectedImages({
    required String userId,
    required String itemUuid,
    required Set<String> keepStoragePaths,
  }) async {
    final folder = _storage.ref().child(_itemFolder(userId, itemUuid));
    try {
      final list = await folder.listAll();
      final toDelete =
          list.items.where((ref) => !keepStoragePaths.contains(ref.fullPath));
      // Delete stale images in parallel.
      await Future.wait(toDelete.map((ref) async {
        try {
          await ref.delete();
        } catch (e) {
          if (!_isMissingObjectError(e)) rethrow;
        }
      }));
    } catch (e) {
      if (!_isMissingObjectError(e)) {
        debugPrint('FirebaseImageUploadService prune error: $e');
      }
    }
  }

  bool _isMissingObjectError(dynamic error) {
    final str = error.toString().toLowerCase();
    if (str.contains('object-not-found') || 
        str.contains('no object exists') ||
        str.contains('not-found')) {
      return true;
    }
    if (error is FirebaseException) {
      return error.code == 'object-not-found' ||
          (error.message?.toLowerCase().contains('no object exists') ?? false);
    }
    return false;
  }

  String _itemFolder(String userId, String itemUuid) {
    return '${StorageConstants.firebaseItemImagesRoot}/$userId/items/$itemUuid';
  }

  String _storagePathFor({
    required String userId,
    required String itemUuid,
    required int index,
    required String extension,
  }) {
    return '${_itemFolder(userId, itemUuid)}/image_$index$extension';
  }

  String? _tryResolveStoragePath(String url) {
    try {
      return _storage.refFromURL(url).fullPath;
    } catch (_) {
      return null;
    }
  }

  Future<_CachedUpload?> _tryReuseExistingUpload({
    required Reference ref,
    required _LocalFileState localFileState,
    String? cacheKey,
  }) async {
    try {
      final metadata = await ref.getMetadata();
      if (!_matchesLocalFile(metadata, localFileState)) {
        return null;
      }

      final downloadUrl = await ref.getDownloadURL();
      final cached = _CachedUpload(
        fullPath: ref.fullPath,
        downloadUrl: downloadUrl,
      );
      if (cacheKey != null) {
        _uploadCache[cacheKey] = cached;
      }
      return cached;
    } catch (e) {
      if (_isMissingObjectError(e)) {
        return null;
      }
      debugPrint(
        'FirebaseImageUploadService: reuse check failed for ${ref.fullPath}: $e',
      );
      return null;
    }
  }

  bool _matchesLocalFile(
    FullMetadata metadata,
    _LocalFileState localFileState,
  ) {
    final customMetadata = metadata.customMetadata;
    if (customMetadata == null) return false;

    return customMetadata[_sourceModifiedMsKey] ==
            localFileState.modifiedMs.toString() &&
        customMetadata[_sourceBytesKey] == localFileState.byteSize.toString();
  }

  Future<_LocalFileState?> _localFileState(String localPath) async {
    final file = File(localPath);
    if (!await file.exists()) return null;

    final stat = await file.stat();
    return _LocalFileState(
      modifiedMs: stat.modified.millisecondsSinceEpoch,
      byteSize: stat.size,
    );
  }

  String _cacheKeyFor({
    required String localPath,
    required String storagePath,
    required int modifiedMs,
    required int byteSize,
  }) {
    return '$storagePath|$localPath|$modifiedMs|$byteSize';
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort temporary file cleanup.
    }
  }
}

class _UploadSlotResult {
  const _UploadSlotResult({this.downloadUrl, this.storagePath});

  final String? downloadUrl;
  final String? storagePath;
}

class _CachedUpload {
  const _CachedUpload({
    required this.fullPath,
    required this.downloadUrl,
  });

  final String fullPath;
  final String downloadUrl;
}

class _LocalFileState {
  const _LocalFileState({
    required this.modifiedMs,
    required this.byteSize,
  });

  final int modifiedMs;
  final int byteSize;
}
