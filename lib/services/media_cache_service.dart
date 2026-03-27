import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/storage_constants.dart';
import '../data/database/media_cache_dao.dart';
import '../domain/models/cloud_media_descriptor.dart';
import '../domain/models/cloud_diagnostics_snapshot.dart';
import '../domain/models/media_cache_entry.dart';
import 'cloud_observation_service.dart';

/// Persistent local cache for cloud media assets.
///
/// Phase 3 keeps this service additive only. Existing UI and restore flows may
/// continue using legacy image and invoice fields, while later phases can call
/// into this service to avoid repeat Firebase Storage downloads.
class MediaCacheService {
  MediaCacheService({
    required FirebaseStorage storage,
    required MediaCacheDao mediaCacheDao,
    required CloudObservationService cloudObservationService,
  })  : _storage = storage,
        _mediaCacheDao = mediaCacheDao,
        _cloudObservationService = cloudObservationService;

  final FirebaseStorage _storage;
  final MediaCacheDao _mediaCacheDao;
  final CloudObservationService _cloudObservationService;
  final Map<String, Future<File?>> _inFlightDownloads = {};

  Future<File?> getCachedThumbOrDownload({
    required CloudMediaDescriptor descriptor,
  }) async {
    final thumbnailPath = descriptor.thumbnailPath?.trim() ?? '';
    if (thumbnailPath.isEmpty) {
      debugPrint(
        '[IkeepMediaCache] thumb descriptor missing path=${descriptor.storagePath}',
      );
      return null;
    }

    return _getCachedOrDownload(
      mediaType: CachedMediaType.thumbnail,
      storagePath: thumbnailPath,
      mimeType: descriptor.mimeType,
      version: descriptor.version,
    );
  }

  Future<File?> getCachedFullImageOrDownload({
    required CloudMediaDescriptor descriptor,
  }) {
    return _getCachedOrDownload(
      mediaType: CachedMediaType.fullImage,
      storagePath: descriptor.storagePath,
      mimeType: descriptor.mimeType,
      version: descriptor.version,
      contentHash: descriptor.contentHash,
    );
  }

  Future<File?> getCachedPdfOrDownload({
    required CloudMediaDescriptor descriptor,
  }) {
    return _getCachedOrDownload(
      mediaType: CachedMediaType.pdf,
      storagePath: descriptor.storagePath,
      mimeType: descriptor.mimeType,
      version: descriptor.version,
      contentHash: descriptor.contentHash,
    );
  }

  Future<bool> isCacheEntryValid({
    required MediaCacheEntry entry,
    required CachedMediaType mediaType,
    required String expectedStoragePath,
    int? expectedVersion,
    String? expectedContentHash,
  }) async {
    if (entry.mediaType != mediaType) {
      return false;
    }
    if (entry.storagePath != expectedStoragePath) {
      return false;
    }

    final localFilePath = entry.localFilePath.trim();
    if (localFilePath.isEmpty) {
      return false;
    }

    final file = File(localFilePath);
    if (!await file.exists()) {
      return false;
    }

    final stat = await file.stat();
    if (stat.size <= 0) {
      return false;
    }

    final normalizedExpectedHash = _normalizedOrNull(expectedContentHash);
    final normalizedEntryHash = _normalizedOrNull(entry.contentHash);
    final hashMatches = normalizedExpectedHash != null &&
        normalizedEntryHash == normalizedExpectedHash;
    final versionMatches =
        expectedVersion != null && entry.version == expectedVersion;
    return hashMatches || versionMatches;
  }

  Future<void> touchCacheEntry(String cacheKey) {
    return _mediaCacheDao.updateLastAccessedAt(
      cacheKey: cacheKey,
      lastAccessedAt: DateTime.now(),
    );
  }

  Future<int> clearInvalidCacheEntries() async {
    final entries = await _mediaCacheDao.getAllEntries();
    var removedCount = 0;

    for (final entry in entries) {
      final localFilePath = entry.localFilePath.trim();
      final file = File(localFilePath);
      final hasVersionOrHash =
          entry.version != null || _normalizedOrNull(entry.contentHash) != null;
      final hasCoreMetadata =
          entry.cacheKey.trim().isNotEmpty &&
          entry.storagePath.trim().isNotEmpty &&
          localFilePath.isNotEmpty &&
          entry.mimeType.trim().isNotEmpty;

      final fileExists = await file.exists();
      final fileSize = fileExists ? (await file.stat()).size : 0;
      final isValid = hasCoreMetadata && hasVersionOrHash && fileExists && fileSize > 0;

      if (isValid) {
        continue;
      }

      if (fileExists) {
        await _safeDelete(file);
      }
      await _mediaCacheDao.deleteByCacheKey(entry.cacheKey);
      removedCount++;
    }

    return removedCount;
  }

  Future<int> removeOrphanedCacheEntries() async {
    var removedCount = await clearInvalidCacheEntries();
    final entries = await _mediaCacheDao.getAllEntries();
    final referencedPaths = entries
        .map((entry) => _normalizeLocalPath(entry.localFilePath))
        .where((path) => path.isNotEmpty)
        .toSet();

    final rootDirectory = await _cacheRootDirectory();
    if (!await rootDirectory.exists()) {
      return removedCount;
    }

    await for (final entity
        in rootDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final normalizedFilePath = _normalizeLocalPath(entity.path);
      if (referencedPaths.contains(normalizedFilePath)) {
        continue;
      }

      await _safeDelete(entity);
      removedCount++;
    }

    return removedCount;
  }

  Future<MediaCacheDiagnosticsSummary> inspectCacheSummary() async {
    final entries = await _mediaCacheDao.getAllEntries();
    final referencedPaths = <String>{};
    var thumbnailCount = 0;
    var fullImageCount = 0;
    var pdfCount = 0;
    var invalidEntryCount = 0;
    var estimatedCacheBytes = 0;

    for (final entry in entries) {
      final normalizedLocalPath = _normalizeLocalPath(entry.localFilePath);
      if (normalizedLocalPath.isNotEmpty) {
        referencedPaths.add(normalizedLocalPath);
      }

      final file = File(entry.localFilePath);
      final fileExists = await file.exists();
      final fileSize = fileExists ? (await file.stat()).size : 0;
      final hasVersionOrHash =
          entry.version != null || _normalizedOrNull(entry.contentHash) != null;
      final hasCoreMetadata =
          entry.cacheKey.trim().isNotEmpty &&
          entry.storagePath.trim().isNotEmpty &&
          normalizedLocalPath.isNotEmpty &&
          entry.mimeType.trim().isNotEmpty;
      final isValid =
          hasCoreMetadata && hasVersionOrHash && fileExists && fileSize > 0;

      if (!isValid) {
        invalidEntryCount++;
        continue;
      }

      estimatedCacheBytes += fileSize;
      switch (entry.mediaType) {
        case CachedMediaType.thumbnail:
          thumbnailCount++;
          break;
        case CachedMediaType.fullImage:
          fullImageCount++;
          break;
        case CachedMediaType.pdf:
          pdfCount++;
          break;
      }
    }

    var orphanFileCount = 0;
    final rootDirectory = await _cacheRootDirectory();
    if (await rootDirectory.exists()) {
      await for (final entity
          in rootDirectory.list(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final normalizedFilePath = _normalizeLocalPath(entity.path);
        if (referencedPaths.contains(normalizedFilePath)) {
          continue;
        }
        orphanFileCount++;
        estimatedCacheBytes += (await entity.stat()).size;
      }
    }

    return MediaCacheDiagnosticsSummary(
      thumbnailCount: thumbnailCount,
      fullImageCount: fullImageCount,
      pdfCount: pdfCount,
      invalidEntryCount: invalidEntryCount,
      orphanFileCount: orphanFileCount,
      estimatedCacheBytes: estimatedCacheBytes,
    );
  }

  Future<File?> _getCachedOrDownload({
    required CachedMediaType mediaType,
    required String storagePath,
    required String mimeType,
    int? version,
    String? contentHash,
  }) {
    final normalizedStoragePath = storagePath.trim();
    if (normalizedStoragePath.isEmpty) {
      return Future.value(null);
    }

    final cacheKey = _cacheKeyFor(
      mediaType: mediaType,
      storagePath: normalizedStoragePath,
      version: version,
      contentHash: contentHash,
    );
    final inFlight = _inFlightDownloads[cacheKey];
    if (inFlight != null) {
      debugPrint(
        '[IkeepMediaCache] awaiting in-flight download '
        'type=$mediaType path=$normalizedStoragePath',
      );
      return inFlight;
    }

    final future = _getCachedOrDownloadInternal(
      cacheKey: cacheKey,
      mediaType: mediaType,
      storagePath: normalizedStoragePath,
      mimeType: mimeType,
      version: version,
      contentHash: contentHash,
    );
    _inFlightDownloads[cacheKey] = future;
    return future.whenComplete(() {
      _inFlightDownloads.remove(cacheKey);
    });
  }

  Future<File?> _getCachedOrDownloadInternal({
    required String cacheKey,
    required CachedMediaType mediaType,
    required String storagePath,
    required String mimeType,
    int? version,
    String? contentHash,
  }) async {
    MediaCacheEntry? entry = await _mediaCacheDao.getByCacheKey(cacheKey);
    entry ??= await _mediaCacheDao.getLatestByStoragePath(
      storagePath: storagePath,
      mediaType: mediaType,
    );

    if (entry != null) {
      final isValid = await isCacheEntryValid(
        entry: entry,
        mediaType: mediaType,
        expectedStoragePath: storagePath,
        expectedVersion: version,
        expectedContentHash: contentHash,
      );
      if (isValid) {
        debugPrint(
          '[IkeepMediaCache] cache hit type=$mediaType path=$storagePath',
        );
        await touchCacheEntry(entry.cacheKey);
        return File(entry.localFilePath);
      }

      debugPrint(
        '[IkeepMediaCache] cache invalidated type=$mediaType path=$storagePath',
      );
      await _removeEntryAndFile(entry);
    }

    debugPrint(
      '[IkeepMediaCache] cache miss type=$mediaType path=$storagePath',
    );

    try {
      final targetFile = await _targetFileFor(
        cacheKey: cacheKey,
        mediaType: mediaType,
        storagePath: storagePath,
        mimeType: mimeType,
      );
      final ref = _storageRefFor(storagePath);
      await ref.writeToFile(targetFile);
      final stat = await targetFile.stat();
      if (stat.size <= 0) {
        await _safeDelete(targetFile);
        return null;
      }

      final now = DateTime.now();
      final cacheEntry = MediaCacheEntry(
        cacheKey: cacheKey,
        mediaType: mediaType,
        storagePath: storagePath,
        version: version,
        contentHash: _normalizedOrNull(contentHash),
        localFilePath: targetFile.path,
        mimeType: mimeType,
        byteSize: stat.size,
        createdAt: now,
        lastAccessedAt: now,
      );
      await _mediaCacheDao.upsertEntry(cacheEntry);
      try {
        await _cloudObservationService.recordMediaDownload(
          mediaType: mediaType,
          storagePath: storagePath,
          version: version,
          contentHash: contentHash,
          estimatedBytes: stat.size,
        );
      } catch (error) {
        debugPrint(
          '[IkeepObserve] media download tracking failed '
          'type=$mediaType path=$storagePath error=$error',
        );
      }
      debugPrint(
        '[IkeepMediaCache] downloaded type=$mediaType path=$storagePath '
        'bytes=${stat.size}',
      );
      return targetFile;
    } catch (error) {
      debugPrint(
        'MediaCacheService: failed to download $mediaType from $storagePath: $error',
      );
      return null;
    }
  }

  Future<File> _targetFileFor({
    required String cacheKey,
    required CachedMediaType mediaType,
    required String storagePath,
    required String mimeType,
  }) async {
    final directory = await _directoryForType(mediaType);
    await directory.create(recursive: true);
    final extension = _resolvedFileExtension(
      storagePath: storagePath,
      mimeType: mimeType,
    );
    final fileName = '$cacheKey$extension';
    return File(p.join(directory.path, fileName));
  }

  Future<Directory> _cacheRootDirectory() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return Directory(
      p.join(documentsDirectory.path, StorageConstants.mediaCacheDir),
    );
  }

  Future<Directory> _directoryForType(CachedMediaType mediaType) async {
    final rootDirectory = await _cacheRootDirectory();
    final folderName = switch (mediaType) {
      CachedMediaType.thumbnail => StorageConstants.mediaCacheThumbnailsDir,
      CachedMediaType.fullImage => StorageConstants.mediaCacheImagesDir,
      CachedMediaType.pdf => StorageConstants.mediaCachePdfsDir,
    };
    return Directory(p.join(rootDirectory.path, folderName));
  }

  Reference _storageRefFor(String storagePath) {
    if (storagePath.toLowerCase().startsWith('gs://')) {
      return _storage.refFromURL(storagePath);
    }
    return _storage.ref().child(storagePath);
  }

  String _cacheKeyFor({
    required CachedMediaType mediaType,
    required String storagePath,
    int? version,
    String? contentHash,
  }) {
    final rawKey = [
      mediaType.dbValue,
      storagePath,
      version?.toString() ?? '',
      _normalizedOrNull(contentHash) ?? '',
    ].join('|');
    final bytes = Uint8List.fromList(utf8.encode(rawKey));
    return CloudMediaHashing.hashBytes(bytes);
  }

  String _resolvedFileExtension({
    required String storagePath,
    required String mimeType,
  }) {
    final fromStoragePath = p.extension(storagePath).trim();
    if (fromStoragePath.isNotEmpty) {
      return fromStoragePath;
    }

    switch (mimeType.toLowerCase()) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'application/pdf':
        return '.pdf';
      default:
        return '';
    }
  }

  String? _normalizedOrNull(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String _normalizeLocalPath(String value) {
    if (value.trim().isEmpty) {
      return '';
    }
    return p.normalize(value).replaceAll('\\', '/').toLowerCase();
  }

  Future<void> _removeEntryAndFile(MediaCacheEntry entry) async {
    await _safeDelete(File(entry.localFilePath));
    await _mediaCacheDao.deleteByCacheKey(entry.cacheKey);
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cache cleanup only.
    }
  }
}
