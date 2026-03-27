import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/constants/storage_constants.dart';
import '../data/database/item_cloud_media_dao.dart';
import '../domain/models/cloud_media_descriptor.dart';
import '../domain/models/item.dart';
import '../domain/models/item_cloud_media_reference.dart';
import 'media_cache_service.dart';

/// Restored/shared-item media registry + access layer.
///
/// This keeps metadata-first restore separate from the main [Item] row while
/// giving UI entry points a single place to ask for thumbnail/full-image/PDF
/// paths with cache-aware fallback behavior.
class ItemCloudMediaService {
  const ItemCloudMediaService({
    required FirebaseStorage storage,
    required ItemCloudMediaDao itemCloudMediaDao,
    required MediaCacheService mediaCacheService,
  })  : _storage = storage,
        _itemCloudMediaDao = itemCloudMediaDao,
        _mediaCacheService = mediaCacheService;

  final FirebaseStorage _storage;
  final ItemCloudMediaDao _itemCloudMediaDao;
  final MediaCacheService _mediaCacheService;

  Future<void> replaceForItemFromCloudData({
    required String itemUuid,
    required Map<String, dynamic> data,
  }) async {
    if (itemUuid.trim().isEmpty) return;

    final references = <ItemCloudMediaReference>[
      ..._buildImageReferences(itemUuid: itemUuid, data: data),
      ..._buildInvoiceReferences(itemUuid: itemUuid, data: data),
    ];
    await _itemCloudMediaDao.replaceForItem(
      itemUuid: itemUuid,
      references: references,
    );
    debugPrint(
      '[IkeepMediaAccess] sidecar refreshed for $itemUuid '
      'refs=${references.length}',
    );
  }

  Future<void> deleteForItem(String itemUuid) {
    return _itemCloudMediaDao.deleteForItem(itemUuid);
  }

  Future<List<ItemCloudMediaReference>> getReferencesForItem(String itemUuid) {
    return _itemCloudMediaDao.getReferencesForItem(itemUuid);
  }

  Future<List<ItemCloudMediaReference>> getImageReferencesForItem(
    String itemUuid,
  ) async {
    final references = await _itemCloudMediaDao.getReferencesForItem(itemUuid);
    return references
        .where((reference) => reference.mediaRole == ItemCloudMediaRole.image)
        .toList(growable: false);
  }

  Future<ItemCloudMediaReference?> getInvoiceReferenceForItem(
    String itemUuid,
  ) {
    return _itemCloudMediaDao.getInvoiceReference(itemUuid);
  }

  Future<void> reconcileForLocalItemUpdate({
    required Item? previousItem,
    required Item nextItem,
  }) async {
    if (previousItem == null) return;

    final existingReferences =
        await _itemCloudMediaDao.getReferencesForItem(nextItem.uuid);
    if (existingReferences.isEmpty) return;

    final imageReferences = existingReferences
        .where((reference) => reference.mediaRole == ItemCloudMediaRole.image)
        .toList(growable: false);
    final invoiceReference = existingReferences
        .where((reference) => reference.mediaRole == ItemCloudMediaRole.invoice)
        .firstOrNull;

    final preservedReferences = <ItemCloudMediaReference>[
      ..._preserveImageReferences(
        previousItem: previousItem,
        nextItem: nextItem,
        existingReferences: imageReferences,
      ),
      if (_shouldPreserveInvoiceReference(
        previousItem: previousItem,
        nextItem: nextItem,
        existingReference: invoiceReference,
      ) &&
          invoiceReference != null)
        invoiceReference,
    ];

    debugPrint(
      '[IkeepMediaAccess] sidecar reconcile for ${nextItem.uuid} '
      'existing=${existingReferences.length} preserved=${preservedReferences.length}',
    );

    final droppedCount = existingReferences.length - preservedReferences.length;
    if (droppedCount > 0) {
      debugPrint(
        '[IkeepMediaAccess] sidecar pruned for ${nextItem.uuid} '
        'dropped=$droppedCount preserved=${preservedReferences.length}',
      );
    }

    await _itemCloudMediaDao.replaceForItem(
      itemUuid: nextItem.uuid,
      references: preservedReferences,
    );
  }

  List<String> restoredImagePathsFromCloudData(Map<String, dynamic> data) {
    final rawImagePaths =
        List<String>.from((data['imagePaths'] as List?) ?? const []);
    final storagePaths =
        List<String>.from((data['imageStoragePaths'] as List?) ?? const []);
    final pathCount =
        rawImagePaths.length > storagePaths.length
            ? rawImagePaths.length
            : storagePaths.length;
    if (pathCount == 0) {
      return const [];
    }

    final restoredPaths = <String>[];
    for (var index = 0; index < pathCount; index++) {
      final rawPath = index < rawImagePaths.length
          ? rawImagePaths[index].trim()
          : '';
      final storagePath = index < storagePaths.length
          ? storagePaths[index].trim()
          : '';
      final resolvedPath = rawPath.isNotEmpty ? rawPath : storagePath;
      if (resolvedPath.isNotEmpty) {
        restoredPaths.add(resolvedPath);
      }
    }
    return restoredPaths;
  }

  String? restoredInvoicePathFromCloudData(Map<String, dynamic> data) {
    final rawInvoicePath = (data['invoicePath'] as String?)?.trim();
    if (rawInvoicePath != null && rawInvoicePath.isNotEmpty) {
      return rawInvoicePath;
    }

    final invoiceStoragePath = (data['invoiceStoragePath'] as String?)?.trim();
    if (invoiceStoragePath != null && invoiceStoragePath.isNotEmpty) {
      return invoiceStoragePath;
    }

    return null;
  }

  Future<String?> resolveImagePath({
    required String itemUuid,
    required int imageIndex,
    required bool preferThumbnail,
    String? fallbackPath,
  }) async {
    final reference = await _itemCloudMediaDao.getImageReference(
      itemUuid: itemUuid,
      slotIndex: imageIndex,
    );
    if (reference == null) {
      debugPrint(
        '[IkeepMediaAccess] image descriptor missing '
        'item=$itemUuid index=$imageIndex',
      );
      final freshFallback = await _tryResolveFreshUrlFromPathCandidate(
        fallbackPath,
      );
      if (freshFallback != null) {
        debugPrint(
          '[IkeepMediaAccess] legacy fallback URL used '
          'item=$itemUuid index=$imageIndex',
        );
        return freshFallback;
      }
      return _sanitizedFallbackPath(fallbackPath);
    }

    debugPrint(
      '[IkeepMediaAccess] image descriptor found '
      'item=$itemUuid index=$imageIndex thumb=${reference.thumbnailPath?.isNotEmpty == true}',
    );

    final descriptor = reference.toDescriptor();
    if (preferThumbnail) {
      if (reference.thumbnailPath?.trim().isEmpty ?? true) {
        debugPrint(
          '[IkeepMediaAccess] thumb descriptor missing '
          'item=$itemUuid index=$imageIndex',
        );
      }
      final cachedThumbnail =
          await _mediaCacheService.getCachedThumbOrDownload(
        descriptor: descriptor,
      );
      if (cachedThumbnail != null) {
        return cachedThumbnail.path;
      }

      final freshThumbUrl = await _tryResolveFreshDownloadUrl(
        reference.thumbnailPath,
      );
      if (freshThumbUrl != null) {
        debugPrint(
          '[IkeepMediaAccess] thumb cache miss using fresh thumb URL '
          'item=$itemUuid index=$imageIndex',
        );
        return freshThumbUrl;
      }

      debugPrint(
        '[IkeepMediaAccess] thumb unavailable '
        'item=$itemUuid index=$imageIndex',
      );

      final sanitizedFallback = _sanitizedFallbackPath(fallbackPath);
      if (sanitizedFallback != null) {
        debugPrint(
          '[IkeepMediaAccess] legacy fallback used for thumb '
          'item=$itemUuid index=$imageIndex',
        );
        return sanitizedFallback;
      }

      final freshImageUrl = await _tryResolveFreshDownloadUrl(
        reference.storagePath,
      );
      if (freshImageUrl != null) {
        debugPrint(
          '[IkeepMediaAccess] full-image URL fallback used for missing thumb '
          'item=$itemUuid index=$imageIndex',
        );
        return freshImageUrl;
      }
      return null;
    }

    final cachedImage = await _mediaCacheService.getCachedFullImageOrDownload(
      descriptor: descriptor,
    );
    if (cachedImage != null) {
      return cachedImage.path;
    }

    final freshImageUrl = await _tryResolveFreshDownloadUrl(reference.storagePath);
    if (freshImageUrl != null) {
      debugPrint(
        '[IkeepMediaAccess] fresh full-image URL fallback used '
        'item=$itemUuid index=$imageIndex',
      );
      return freshImageUrl;
    }

    final sanitizedFallback = _sanitizedFallbackPath(fallbackPath);
    if (sanitizedFallback != null) {
      debugPrint(
        '[IkeepMediaAccess] legacy full-image fallback used '
        'item=$itemUuid index=$imageIndex',
      );
    }
    return sanitizedFallback;
  }

  Future<String?> resolveInvoicePath({
    required String itemUuid,
    String? fallbackPath,
  }) async {
    final reference = await _itemCloudMediaDao.getInvoiceReference(itemUuid);
    if (reference == null) {
      debugPrint('[IkeepMediaAccess] invoice descriptor missing item=$itemUuid');
      final freshFallback = await _tryResolveFreshUrlFromPathCandidate(
        fallbackPath,
      );
      if (freshFallback != null) {
        debugPrint(
          '[IkeepMediaAccess] legacy invoice URL fallback used item=$itemUuid',
        );
        return freshFallback;
      }
      return _sanitizedFallbackPath(fallbackPath);
    }

    debugPrint('[IkeepMediaAccess] invoice descriptor found item=$itemUuid');

    final cachedPdf = await _mediaCacheService.getCachedPdfOrDownload(
      descriptor: reference.toDescriptor(),
    );
    if (cachedPdf != null) {
      debugPrint('[IkeepMediaAccess] invoice cache path used item=$itemUuid');
      return cachedPdf.path;
    }

    final freshInvoiceUrl = await _tryResolveFreshDownloadUrl(reference.storagePath);
    if (freshInvoiceUrl != null) {
      debugPrint(
        '[IkeepMediaAccess] fresh invoice URL fallback used item=$itemUuid',
      );
      return freshInvoiceUrl;
    }

    final sanitizedFallback = _sanitizedFallbackPath(fallbackPath);
    if (sanitizedFallback != null) {
      debugPrint(
        '[IkeepMediaAccess] legacy invoice fallback used item=$itemUuid',
      );
    }
    return sanitizedFallback;
  }

  List<ItemCloudMediaReference> _buildImageReferences({
    required String itemUuid,
    required Map<String, dynamic> data,
  }) {
    final references = <int, ItemCloudMediaReference>{};
    final fallbackUpdatedAt = _fallbackUpdatedAt(data);
    final fallbackVersion = _fallbackVersion(data, fallbackUpdatedAt);

    final imageMedia = data['imageMedia'];
    if (imageMedia is List) {
      for (var index = 0; index < imageMedia.length; index++) {
        final rawEntry = imageMedia[index];
        if (rawEntry is! Map) continue;

        final descriptor = CloudMediaDescriptor.fromJson(
          Map<String, dynamic>.from(rawEntry as Map<dynamic, dynamic>),
        );
        final storagePath = descriptor.storagePath.trim();
        if (storagePath.isEmpty) continue;

        references[index] = ItemCloudMediaReference(
          itemUuid: itemUuid,
          mediaRole: ItemCloudMediaRole.image,
          slotIndex: index,
          storagePath: storagePath,
          thumbnailPath: (descriptor.thumbnailPath?.trim().isNotEmpty ?? false)
              ? descriptor.thumbnailPath
              : _inferredThumbnailPath(storagePath),
          mimeType: descriptor.mimeType,
          byteSize: descriptor.byteSize,
          contentHash: descriptor.contentHash,
          version: descriptor.version,
          updatedAt: descriptor.updatedAt,
        );
      }
    }

    final imageStoragePaths =
        List<String>.from((data['imageStoragePaths'] as List?) ?? const []);
    final rawImagePaths =
        List<String>.from((data['imagePaths'] as List?) ?? const []);
    for (var index = 0; index < imageStoragePaths.length; index++) {
      final storagePath = imageStoragePaths[index].trim();
      if (storagePath.isEmpty || references.containsKey(index)) {
        continue;
      }

      final rawPath =
          index < rawImagePaths.length ? rawImagePaths[index].trim() : '';
      references[index] = ItemCloudMediaReference(
        itemUuid: itemUuid,
        mediaRole: ItemCloudMediaRole.image,
        slotIndex: index,
        storagePath: storagePath,
        thumbnailPath: _inferredThumbnailPath(storagePath),
        mimeType: _imageMimeTypeForPath(
          rawPath.isNotEmpty ? rawPath : storagePath,
        ),
        byteSize: null,
        contentHash: null,
        version: fallbackVersion,
        updatedAt: fallbackUpdatedAt,
      );
    }

    for (var index = 0; index < rawImagePaths.length; index++) {
      if (references.containsKey(index)) {
        continue;
      }

      final rawPath = rawImagePaths[index].trim();
      final storagePath = _normalizeStoragePathCandidate(rawPath);
      if (storagePath == null || storagePath.isEmpty) {
        continue;
      }

      references[index] = ItemCloudMediaReference(
        itemUuid: itemUuid,
        mediaRole: ItemCloudMediaRole.image,
        slotIndex: index,
        storagePath: storagePath,
        thumbnailPath: _inferredThumbnailPath(storagePath),
        mimeType: _imageMimeTypeForPath(rawPath),
        byteSize: null,
        contentHash: null,
        version: fallbackVersion,
        updatedAt: fallbackUpdatedAt,
      );
    }

    final sortedIndexes = references.keys.toList()..sort();
    return sortedIndexes.map((index) => references[index]!).toList();
  }

  List<ItemCloudMediaReference> _buildInvoiceReferences({
    required String itemUuid,
    required Map<String, dynamic> data,
  }) {
    final invoiceMedia = data['invoiceMedia'];
    if (invoiceMedia is Map) {
      final descriptor = CloudMediaDescriptor.fromJson(
        Map<String, dynamic>.from(invoiceMedia as Map<dynamic, dynamic>),
      );
      final storagePath = descriptor.storagePath.trim();
      if (storagePath.isNotEmpty) {
        return [
          ItemCloudMediaReference(
            itemUuid: itemUuid,
            mediaRole: ItemCloudMediaRole.invoice,
            slotIndex: 0,
            storagePath: storagePath,
            thumbnailPath: descriptor.thumbnailPath,
            mimeType: descriptor.mimeType,
            byteSize: descriptor.byteSize,
            contentHash: descriptor.contentHash,
            version: descriptor.version,
            updatedAt: descriptor.updatedAt,
          ),
        ];
      }
    }

    final invoiceStoragePath = (data['invoiceStoragePath'] as String?)?.trim();
    final fallbackInvoiceStoragePath =
        invoiceStoragePath?.isNotEmpty == true
            ? invoiceStoragePath
            : _normalizeStoragePathCandidate(
                (data['invoicePath'] as String?)?.trim(),
              );
    if (fallbackInvoiceStoragePath == null ||
        fallbackInvoiceStoragePath.isEmpty) {
      return const [];
    }

    final fallbackUpdatedAt = _fallbackUpdatedAt(data);
    final fallbackVersion = _fallbackVersion(data, fallbackUpdatedAt);
    final invoiceFileName = (data['invoiceFileName'] as String?)?.trim();

    return [
      ItemCloudMediaReference(
        itemUuid: itemUuid,
        mediaRole: ItemCloudMediaRole.invoice,
        slotIndex: 0,
        storagePath: fallbackInvoiceStoragePath,
        mimeType: _invoiceMimeType(
          explicitMimeType: (data['invoiceMimeType'] as String?)?.trim(),
          invoiceFileName: invoiceFileName,
          invoiceStoragePath: fallbackInvoiceStoragePath,
        ),
        byteSize: _nullableInt(
              data['invoiceUploadedFileSizeBytes'],
            ) ??
            _nullableInt(data['invoiceFileSizeBytes']),
        contentHash: null,
        version: fallbackVersion,
        updatedAt: fallbackUpdatedAt,
      ),
    ];
  }

  DateTime _fallbackUpdatedAt(Map<String, dynamic> data) {
    return _parseDateTime(data['lastContentUpdatedAt']) ??
        _parseDateTime(data['updatedAt']) ??
        _parseDateTime(data['createdAt']) ??
        DateTime.now().toUtc();
  }

  int _fallbackVersion(Map<String, dynamic> data, DateTime fallbackUpdatedAt) {
    return _nullableInt(data['syncVersion']) ??
        fallbackUpdatedAt.millisecondsSinceEpoch;
  }

  int? _nullableInt(dynamic value) {
    return (value as num?)?.toInt();
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toUtc();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toUtc();
    }
    return null;
  }

  String? _inferredThumbnailPath(String storagePath) {
    final trimmed = storagePath.trim();
    if (trimmed.isEmpty) return null;

    final extension = p.extension(trimmed);
    final resolvedExtension = extension.isEmpty ? '.webp' : extension;
    final fileName = p.basenameWithoutExtension(trimmed);
    final directory = p.dirname(trimmed).replaceAll('\\', '/');
    return '$directory/$fileName${StorageConstants.firebaseThumbnailSuffix}$resolvedExtension';
  }

  String _imageMimeTypeForPath(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  String _invoiceMimeType({
    String? explicitMimeType,
    String? invoiceFileName,
    required String invoiceStoragePath,
  }) {
    final normalizedExplicit = explicitMimeType?.trim();
    if (normalizedExplicit != null && normalizedExplicit.isNotEmpty) {
      return normalizedExplicit;
    }

    final source = invoiceFileName?.trim().isNotEmpty == true
        ? invoiceFileName!.trim()
        : invoiceStoragePath;
    switch (p.extension(source).toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  String? _sanitizedFallbackPath(String? fallbackPath) {
    final trimmedPath = fallbackPath?.trim();
    if (trimmedPath == null || trimmedPath.isEmpty) {
      return null;
    }
    if (_looksLikeStoragePath(trimmedPath) ||
        trimmedPath.toLowerCase().startsWith('gs://')) {
      return null;
    }
    return trimmedPath;
  }

  bool _looksLikeStoragePath(String path) {
    return path.startsWith('${StorageConstants.firebaseItemImagesRoot}/');
  }

  List<ItemCloudMediaReference> _preserveImageReferences({
    required Item previousItem,
    required Item nextItem,
    required List<ItemCloudMediaReference> existingReferences,
  }) {
    if (existingReferences.isEmpty || nextItem.imagePaths.isEmpty) {
      return const [];
    }

    final preservedReferences = <ItemCloudMediaReference>[];
    final usedReferenceIndexes = <int>{};

    for (var nextIndex = 0; nextIndex < nextItem.imagePaths.length; nextIndex++) {
      final nextPath = nextItem.imagePaths[nextIndex];
      for (final reference in existingReferences) {
        final referenceIndex = reference.slotIndex;
        if (usedReferenceIndexes.contains(referenceIndex) ||
            referenceIndex >= previousItem.imagePaths.length) {
          continue;
        }

        final previousPath = previousItem.imagePaths[referenceIndex];
        if (!_pathsRepresentSameCloudMedia(
          previousPath: previousPath,
          nextPath: nextPath,
          reference: reference,
        )) {
          continue;
        }

        preservedReferences.add(reference.copyWith(slotIndex: nextIndex));
        usedReferenceIndexes.add(referenceIndex);
        break;
      }
    }

    return preservedReferences;
  }

  bool _shouldPreserveInvoiceReference({
    required Item previousItem,
    required Item nextItem,
    required ItemCloudMediaReference? existingReference,
  }) {
    if (existingReference == null) return false;
    return _pathsRepresentSameCloudMedia(
      previousPath: previousItem.invoicePath,
      nextPath: nextItem.invoicePath,
      reference: existingReference,
    );
  }

  bool _pathsRepresentSameCloudMedia({
    required String? previousPath,
    required String? nextPath,
    required ItemCloudMediaReference reference,
  }) {
    final normalizedPreviousPath = previousPath?.trim() ?? '';
    final normalizedNextPath = nextPath?.trim() ?? '';
    if (normalizedPreviousPath.isEmpty || normalizedNextPath.isEmpty) {
      return false;
    }
    if (normalizedPreviousPath == normalizedNextPath) {
      return true;
    }

    final nextStoragePath = _normalizeStoragePathCandidate(normalizedNextPath);
    if (nextStoragePath != null && nextStoragePath == reference.storagePath) {
      return true;
    }

    final previousStoragePath =
        _normalizeStoragePathCandidate(normalizedPreviousPath);
    if (previousStoragePath != null &&
        previousStoragePath == reference.storagePath &&
        nextStoragePath == previousStoragePath) {
      return true;
    }

    return false;
  }

  String? _normalizeStoragePathCandidate(String? value) {
    final trimmedValue = value?.trim();
    if (trimmedValue == null || trimmedValue.isEmpty) {
      return null;
    }
    if (_looksLikeStoragePath(trimmedValue)) {
      return trimmedValue;
    }

    try {
      final ref = trimmedValue.toLowerCase().startsWith('gs://') ||
              trimmedValue.toLowerCase().startsWith('http://') ||
              trimmedValue.toLowerCase().startsWith('https://')
          ? _storage.refFromURL(trimmedValue)
          : null;
      return ref?.fullPath;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _tryResolveFreshUrlFromPathCandidate(String? value) async {
    final storagePath = _normalizeStoragePathCandidate(value);
    if (storagePath == null || storagePath.isEmpty) {
      return null;
    }
    return _tryResolveFreshDownloadUrl(storagePath);
  }

  Future<String?> _tryResolveFreshDownloadUrl(String? storagePath) async {
    final trimmedPath = storagePath?.trim() ?? '';
    if (trimmedPath.isEmpty) {
      return null;
    }

    try {
      return await _storage.ref().child(trimmedPath).getDownloadURL();
    } catch (error) {
      debugPrint(
        '[IkeepMediaAccess] failed fresh URL lookup for $trimmedPath: $error',
      );
      return null;
    }
  }
}
