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

  /// Resolves image paths restored from cloud into displayable download URLs.
  ///
  /// Older backups may have an empty `imagePaths` array in Firestore even when
  /// the actual image files still exist in Firebase Storage. Some legacy data
  /// may also store `gs://` or raw storage paths, which `Image.network` cannot
  /// render directly. This helper normalizes those cases and falls back to the
  /// item's storage folder when needed.
  Future<List<String>> resolveCloudImageUrls({
    required String userId,
    required String itemUuid,
    Iterable<String> imagePaths = const <String>[],
  }) async {
    final resolvedUrls = <String>[];
    final seen = <String>{};

    for (final imagePath in imagePaths) {
      final resolvedUrl = await _resolveCloudImageUrl(imagePath);
      if (resolvedUrl == null || resolvedUrl.trim().isEmpty) continue;
      if (seen.add(resolvedUrl)) {
        resolvedUrls.add(resolvedUrl);
      }
    }

    if (resolvedUrls.isNotEmpty) {
      return resolvedUrls;
    }

    return _listStoredItemImageUrls(userId: userId, itemUuid: itemUuid);
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
    if (localFileState == null) {
      final reusedRemote = await _tryReuseStoredSlotImage(
        userId: userId,
        itemUuid: itemUuid,
        index: index,
        preferredRef: ref,
      );
      if (reusedRemote != null) {
        return reusedRemote;
      }

      debugPrint(
        'FirebaseImageUploadService: missing local image for slot $index, skipping $path',
      );
      return const _UploadSlotResult();
    }

    final cacheKey = _cacheKeyFor(
      localPath: path,
      storagePath: storagePath,
      modifiedMs: localFileState.modifiedMs,
      byteSize: localFileState.byteSize,
    );

    // 1. In-memory cache hit.
    final cached = _uploadCache[cacheKey];
    if (cached != null) {
      return _UploadSlotResult(
        downloadUrl: cached.downloadUrl,
        storagePath: cached.fullPath,
      );
    }

    // 2. Reuse existing upload on Firebase Storage.
    final reused = await _tryReuseExistingUpload(
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
            _sourceModifiedMsKey: localFileState.modifiedMs.toString(),
            _sourceBytesKey: localFileState.byteSize.toString(),
          },
        ),
      );

      final downloadUrl = await ref.getDownloadURL();
      _uploadCache[cacheKey] = _CachedUpload(
        fullPath: ref.fullPath,
        downloadUrl: downloadUrl,
      );
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

  Future<_UploadSlotResult?> _tryReuseStoredSlotImage({
    required String userId,
    required String itemUuid,
    required int index,
    required Reference preferredRef,
  }) async {
    try {
      final downloadUrl = await preferredRef.getDownloadURL();
      return _UploadSlotResult(
        downloadUrl: downloadUrl,
        storagePath: preferredRef.fullPath,
      );
    } catch (e) {
      if (!_isMissingObjectError(e)) {
        debugPrint(
          'FirebaseImageUploadService: failed remote reuse for ${preferredRef.fullPath}: $e',
        );
        return null;
      }
    }

    try {
      final folder = _storage.ref().child(_itemFolder(userId, itemUuid));
      final list = await folder.listAll();
      final filePrefix = 'image_$index.';

      for (final candidate in list.items) {
        final fileName = candidate.fullPath.split('/').last;
        if (!fileName.startsWith(filePrefix)) continue;

        try {
          final downloadUrl = await candidate.getDownloadURL();
          return _UploadSlotResult(
            downloadUrl: downloadUrl,
            storagePath: candidate.fullPath,
          );
        } catch (e) {
          if (!_isMissingObjectError(e)) {
            debugPrint(
              'FirebaseImageUploadService: failed legacy remote reuse for ${candidate.fullPath}: $e',
            );
          }
        }
      }
    } catch (e) {
      if (!_isMissingObjectError(e)) {
        debugPrint('FirebaseImageUploadService slot lookup error: $e');
      }
    }

    return null;
  }

  Future<String?> _resolveCloudImageUrl(String path) async {
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) return null;

    final normalizedPath = trimmedPath.toLowerCase();
    if (normalizedPath.startsWith('http://') ||
        normalizedPath.startsWith('https://')) {
      return trimmedPath;
    }

    if (normalizedPath.startsWith('gs://')) {
      try {
        return await _storage.refFromURL(trimmedPath).getDownloadURL();
      } catch (e) {
        if (!_isMissingObjectError(e)) {
          debugPrint(
            'FirebaseImageUploadService: failed to resolve gs url $trimmedPath: $e',
          );
        }
        return null;
      }
    }

    if (trimmedPath.contains('/')) {
      try {
        return await _storage.ref().child(trimmedPath).getDownloadURL();
      } catch (e) {
        if (!_isMissingObjectError(e)) {
          debugPrint(
            'FirebaseImageUploadService: failed to resolve storage path $trimmedPath: $e',
          );
        }
      }
    }

    return null;
  }

  Future<List<String>> _listStoredItemImageUrls({
    required String userId,
    required String itemUuid,
  }) async {
    try {
      final folder = _storage.ref().child(_itemFolder(userId, itemUuid));
      final list = await folder.listAll();
      final refs = [...list.items]..sort(_compareStorageRefsBySlot);

      final urls = <String>[];
      for (final ref in refs) {
        try {
          urls.add(await ref.getDownloadURL());
        } catch (e) {
          if (!_isMissingObjectError(e)) {
            debugPrint(
              'FirebaseImageUploadService: failed to restore ${ref.fullPath}: $e',
            );
          }
        }
      }
      return urls;
    } catch (e) {
      if (!_isMissingObjectError(e)) {
        debugPrint(
          'FirebaseImageUploadService: failed to list cloud images for $itemUuid: $e',
        );
      }
      return const [];
    }
  }

  int _compareStorageRefsBySlot(Reference a, Reference b) {
    final aSlot = _slotIndexForPath(a.fullPath);
    final bSlot = _slotIndexForPath(b.fullPath);
    if (aSlot != bSlot) {
      return aSlot.compareTo(bSlot);
    }
    return a.fullPath.compareTo(b.fullPath);
  }

  int _slotIndexForPath(String fullPath) {
    final fileName = fullPath.split('/').last;
    final match = RegExp(r'image_(\d+)').firstMatch(fileName);
    if (match == null) {
      return 1 << 30;
    }
    return int.tryParse(match.group(1) ?? '') ?? (1 << 30);
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
