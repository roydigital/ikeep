import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/storage_constants.dart';
import '../core/utils/path_utils.dart';
import 'image_optimizer_service.dart';

/// The result of uploading all images for one item.
///
/// Both lists are in the same slot order (index 0 = image_0, etc.).
/// [downloadUrls] contains HTTPS Firebase Storage download URLs that can be
/// used with Image.network() immediately — they may become stale if the
/// underlying Storage object is re-uploaded or the token is revoked.
/// [storagePaths] contains the authoritative Firebase Storage object paths
/// (e.g. "users/uid/items/uuid/image_0.webp") that never expire and can
/// always be used to fetch a fresh download URL.
class ImageUploadResult {
  const ImageUploadResult({
    required this.downloadUrls,
    required this.storagePaths,
  });

  /// HTTPS download URLs — fast to display, may become stale over time.
  final List<String> downloadUrls;

  /// Firebase Storage object paths — durable, use to refresh stale URLs.
  final List<String> storagePaths;

  /// Returns true if at least one image was successfully uploaded/resolved.
  bool get hasImages => downloadUrls.isNotEmpty;

  /// Returns true when every slot produced both a URL and a storage path.
  bool get isFullyUploaded =>
      downloadUrls.length == storagePaths.length && downloadUrls.isNotEmpty;
}

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

  /// Uploads all images for [itemUuid] to Firebase Storage and returns both
  /// the HTTPS download URLs (for immediate display) and the durable Storage
  /// object paths (for refresh when URLs go stale).
  ///
  /// If [imagePaths] is empty all existing Storage images are deleted and
  /// an empty [ImageUploadResult] is returned.
  Future<ImageUploadResult> uploadItemImages({
    required String userId,
    required String itemUuid,
    required List<String> imagePaths,
  }) async {
    debugPrint(
      '[IkeepUpload] uploadItemImages: itemUuid=$itemUuid '
      'imageCount=${imagePaths.length}',
    );

    if (imagePaths.isEmpty) {
      debugPrint('[IkeepUpload] No images to upload — deleting any stale Storage files');
      await deleteItemImages(userId: userId, itemUuid: itemUuid);
      return const ImageUploadResult(downloadUrls: [], storagePaths: []);
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
    final storagePaths = <String>[];
    final keepStoragePaths = <String>{};

    for (final result in results) {
      if (result.downloadUrl != null) {
        downloadUrls.add(result.downloadUrl!);
      }
      if (result.storagePath != null) {
        storagePaths.add(result.storagePath!);
        keepStoragePaths.add(result.storagePath!);
      }
    }

    debugPrint(
      '[IkeepUpload] uploadItemImages complete: '
      '${downloadUrls.length}/${imagePaths.length} uploaded, '
      'storagePaths=$storagePaths',
    );

    // Prune stale images in the background — no need to block the caller.
    _pruneUnexpectedImages(
      userId: userId,
      itemUuid: itemUuid,
      keepStoragePaths: keepStoragePaths,
    );

    return ImageUploadResult(
      downloadUrls: downloadUrls,
      storagePaths: storagePaths,
    );
  }

  /// Resolves image paths from a cloud restore into displayable HTTPS URLs.
  ///
  /// **Primary path** — [storagePaths] (Firebase Storage object paths, e.g.
  /// "users/uid/items/uuid/image_0.webp") are used to call [getDownloadURL()]
  /// and get a guaranteed-fresh URL. This is the correct path after a
  /// reinstall because the stored download URL may have become stale.
  ///
  /// **Fallback 1** — if no storage paths are provided (legacy backup docs
  /// that predate the storage-path field), [downloadUrls] are tried as-is.
  ///
  /// **Fallback 2** — if both are empty or all resolutions fail, the service
  /// lists the item's Storage folder and returns whatever files it finds.
  Future<List<String>> resolveItemImageUrls({
    required String userId,
    required String itemUuid,
    List<String> downloadUrls = const [],
    List<String> storagePaths = const [],
  }) async {
    // ── Primary: use durable storage paths to get fresh download URLs ────────
    if (storagePaths.isNotEmpty) {
      final freshUrls = await _resolveFromStoragePaths(storagePaths);
      if (freshUrls.isNotEmpty) {
        debugPrint(
          'FirebaseImageUploadService: resolved ${freshUrls.length} '
          'fresh URL(s) from storage paths for $itemUuid',
        );
        return freshUrls;
      }
      // Storage paths exist but files are gone — log clearly.
      debugPrint(
        'FirebaseImageUploadService: could not get fresh URLs for $itemUuid '
        'via storage paths (files deleted or Storage rules block read) — '
        'falling back to stored download URLs',
      );
    }

    // ── Fallback 1: use stored download URLs (legacy / pre-storagePaths) ─────
    if (downloadUrls.isNotEmpty) {
      final resolvedUrls = await resolveCloudImageUrls(
        userId: userId,
        itemUuid: itemUuid,
        imagePaths: downloadUrls,
      );
      if (resolvedUrls.isNotEmpty) return resolvedUrls;
    }

    // ── Fallback 2: list the item's Storage folder ────────────────────────────
    return _listStoredItemImageUrls(userId: userId, itemUuid: itemUuid);
  }

  /// Resolves image paths restored from cloud into displayable download URLs.
  ///
  /// Older backups may have an empty `imagePaths` array in Firestore even when
  /// the actual image files still exist in Firebase Storage. Some legacy data
  /// may also store `gs://` or raw storage paths, which `Image.network` cannot
  /// render directly. This helper normalises those cases and falls back to the
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

    // Already a remote URL or gs:// path — nothing to upload. Resolve the
    // storage path so we can store it as the canonical durable reference.
    if (PathUtils.isRemotePath(path)) {
      final fullPath = _tryResolveStoragePath(path);
      // If it's a gs:// URI, get a fresh download URL.
      if (path.trim().toLowerCase().startsWith('gs://')) {
        try {
          final downloadUrl = await _storage.refFromURL(path).getDownloadURL();
          debugPrint(
            '[IkeepUpload] slot $index resolved gs:// → downloadUrl received',
          );
          return _UploadSlotResult(
            downloadUrl: downloadUrl,
            storagePath: fullPath,
          );
        } catch (e) {
          if (!_isMissingObjectError(e)) {
            debugPrint(
              '[IkeepUpload] slot $index failed to resolve gs:// URL $path: $e',
            );
          }
          return const _UploadSlotResult();
        }
      }
      // HTTPS URL — return as-is with its storage path for future refresh.
      debugPrint('[IkeepUpload] slot $index: already a remote URL, skipping upload');
      return _UploadSlotResult(downloadUrl: path, storagePath: fullPath);
    }

    debugPrint('[IkeepUpload] slot $index: local file selected → $path');

    final storagePath = _storagePathFor(
      userId: userId,
      itemUuid: itemUuid,
      index: index,
      extension: _optimizer.preferredUploadExtension,
    );
    final ref = _storage.ref().child(storagePath);
    final localFileState = await _localFileState(path);
    if (localFileState == null) {
      debugPrint(
        '[IkeepUpload] slot $index: local file missing at $path — '
        'trying to reuse previously-uploaded Storage file',
      );
      final reusedRemote = await _tryReuseStoredSlotImage(
        userId: userId,
        itemUuid: itemUuid,
        index: index,
        preferredRef: ref,
      );
      if (reusedRemote != null) {
        debugPrint('[IkeepUpload] slot $index: reused existing Storage file');
        return reusedRemote;
      }

      debugPrint(
        '[IkeepUpload] slot $index: no local file and no existing Storage '
        'file — skipping slot. Path was: $path',
      );
      return const _UploadSlotResult();
    }

    debugPrint(
      '[IkeepUpload] slot $index: local file found — '
      '${localFileState.byteSize} bytes, '
      'modified ${DateTime.fromMillisecondsSinceEpoch(localFileState.modifiedMs)}',
    );

    final cacheKey = _cacheKeyFor(
      localPath: path,
      storagePath: storagePath,
      modifiedMs: localFileState.modifiedMs,
      byteSize: localFileState.byteSize,
    );

    // 1. In-memory cache hit.
    final cached = _uploadCache[cacheKey];
    if (cached != null) {
      debugPrint('[IkeepUpload] slot $index: in-memory cache hit, skipping upload');
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
      debugPrint('[IkeepUpload] slot $index: reused existing Storage upload');
      return _UploadSlotResult(
        downloadUrl: reused.downloadUrl,
        storagePath: reused.fullPath,
      );
    }

    // 3. Optimize and upload.
    debugPrint(
      '[IkeepUpload] slot $index: optimizing image for upload → $storagePath',
    );
    final optimized = await _optimizer.optimizeForUpload(path);
    debugPrint(
      '[IkeepUpload] slot $index: optimized to ${optimized.byteSize} bytes '
      '(${optimized.contentType}) — starting putFile',
    );
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
      debugPrint('[IkeepUpload] slot $index: putFile SUCCESS → fetching download URL');

      final downloadUrl = await ref.getDownloadURL();
      debugPrint('[IkeepUpload] slot $index: download URL received ✓');
      _uploadCache[cacheKey] = _CachedUpload(
        fullPath: ref.fullPath,
        downloadUrl: downloadUrl,
      );
      return _UploadSlotResult(
        downloadUrl: downloadUrl,
        storagePath: ref.fullPath,
      );
    } catch (e) {
      // Do NOT swallow putFile errors with _isMissingObjectError — that check
      // matches any error containing "not-found", including
      // [firebase_storage/bucket-not-found] when Storage is not set up.
      // Silently returning empty here is the root cause of the "Storage always
      // empty" bug: uploads fail invisibly and Firestore is written with null
      // attachment fields instead. Always rethrow so the caller surfaces the
      // real error.
      debugPrint(
        '[IkeepUpload] slot $index: UPLOAD FAILED for $path\n'
        '  storagePath=$storagePath\n'
        '  error=$e\n'
        '  >>> Check Firebase Storage security rules and bucket configuration <<<',
      );
      rethrow;
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

  /// Converts [storagePaths] (Firebase Storage object paths) into fresh HTTPS
  /// download URLs by calling [getDownloadURL()] directly on each ref.
  /// Missing objects are skipped; other errors are logged and skipped.
  ///
  /// NOTE: [getDownloadURL()] requires `read` permission in Firebase Storage
  /// security rules. If this returns an empty list despite images being
  /// present in Storage, check your Firebase Storage rules — they must allow:
  ///   match /users/{userId}/{allPaths=**} {
  ///     allow read: if request.auth != null && request.auth.uid == userId;
  ///   }
  Future<List<String>> _resolveFromStoragePaths(
    List<String> storagePaths,
  ) async {
    final urls = <String>[];
    for (final storagePath in storagePaths) {
      if (storagePath.trim().isEmpty) continue;
      try {
        final ref = storagePath.toLowerCase().startsWith('gs://')
            ? _storage.refFromURL(storagePath)
            : _storage.ref().child(storagePath);
        final url = await ref.getDownloadURL();
        urls.add(url);
      } catch (e) {
        if (_isMissingObjectError(e)) {
          // File was deleted from Storage — skip silently.
        } else {
          // Likely a permission-denied error: Firebase Storage security rules
          // may not allow read access for this user. The fallback to stored
          // HTTPS download URLs (rawImagePaths) will be tried next.
          debugPrint(
            'FirebaseImageUploadService: getDownloadURL failed for '
            '$storagePath — may be a Storage rules issue: $e',
          );
        }
      }
    }
    return urls;
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
