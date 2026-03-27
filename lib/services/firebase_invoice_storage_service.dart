import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/constants/storage_constants.dart';
import '../core/utils/path_utils.dart';
import 'pdf_optimizer_service.dart';

/// Represents an invoice/PDF file that has been saved to Firebase Storage.
///
/// [path] is an HTTPS download URL — use it to open the file immediately.
/// [storagePath] is the durable Firebase Storage object path (e.g.
/// "users/uid/items/uuid/invoices/invoice.pdf"). Use it to get a fresh
/// download URL when [path] becomes stale after a reinstall.
class StoredInvoiceFile {
  const StoredInvoiceFile({
    required this.path,
    required this.fileName,
    this.sizeBytes,
    this.storagePath,
    this.originalFileName,
    this.originalFileSizeBytes,
    this.mimeType,
    this.compressionApplied = false,
  });

  /// HTTPS download URL — fast to open, may become stale over time.
  final String path;

  /// Human-readable file name (e.g. "receipt.pdf").
  final String fileName;

  /// File size in bytes, if known. After optimization this is the
  /// *uploaded* size, not the original.
  final int? sizeBytes;

  /// Firebase Storage object path — durable, never expires.
  /// Use to call [getDownloadURL()] when [path] is stale.
  final String? storagePath;

  /// Name of the file the user originally selected (before optimization).
  final String? originalFileName;

  /// Size of the original file before any compression, in bytes.
  final int? originalFileSizeBytes;

  /// MIME type of the uploaded file (e.g. "application/pdf").
  final String? mimeType;

  /// Whether the file was compressed/optimized before upload.
  final bool compressionApplied;
}

class FirebaseInvoiceStorageService {
  FirebaseInvoiceStorageService({
    required FirebaseStorage storage,
    required PdfOptimizerService pdfOptimizer,
  })  : _storage = storage,
       _pdfOptimizer = pdfOptimizer;

  final FirebaseStorage _storage;
  final PdfOptimizerService _pdfOptimizer;

  static const _putFileTimeout = Duration(seconds: 90);
  static const _getUrlTimeout = Duration(seconds: 15);
  static const _listAllTimeout = Duration(seconds: 15);
  static const _getMetadataTimeout = Duration(seconds: 10);

  /// Uploads [invoicePath] (a local file path) to Firebase Storage and
  /// returns a [StoredInvoiceFile] with both the HTTPS download URL and the
  /// durable Storage object path.
  ///
  /// If [invoicePath] is already a remote URL it is returned as-is with the
  /// Storage path resolved when possible.
  /// If the local file is missing and a previously-uploaded file exists in
  /// Storage it is reused.
  Future<StoredInvoiceFile?> uploadItemInvoice({
    required String userId,
    required String itemUuid,
    required String? invoicePath,
    String? invoiceFileName,
    int? invoiceFileSizeBytes,
  }) async {
    final trimmedPath = invoicePath?.trim() ?? '';

    debugPrint(
      '[IkeepInvoice] uploadItemInvoice: itemUuid=$itemUuid '
      'hasPath=${trimmedPath.isNotEmpty} '
      'fileName=$invoiceFileName '
      'sizeBytes=$invoiceFileSizeBytes',
    );

    if (trimmedPath.isEmpty) {
      debugPrint('[IkeepInvoice] No invoice path — deleting any stale Storage files');
      await deleteItemInvoice(userId: userId, itemUuid: itemUuid);
      return null;
    }

    if (PathUtils.isRemotePath(trimmedPath)) {
      // Already a remote URL — resolve its Storage path for durability.
      debugPrint('[IkeepInvoice] Invoice is already a remote URL — skipping upload');
      final storagePath = _tryResolveStoragePath(trimmedPath);
      return StoredInvoiceFile(
        path: trimmedPath,
        fileName: _resolvedFileName(trimmedPath, fallback: invoiceFileName),
        sizeBytes: invoiceFileSizeBytes,
        storagePath: storagePath,
      );
    }

    debugPrint('[IkeepInvoice] Local invoice file selected: $trimmedPath');

    final localFile = File(trimmedPath);
    if (!await localFile.exists()) {
      // Local file is missing (e.g. after reinstall) — try to reuse the
      // previously-uploaded file from Storage.
      debugPrint(
        '[IkeepInvoice] Local invoice file missing at $trimmedPath — '
        'trying to reuse previously-uploaded Storage file',
      );
      return _getStoredInvoice(
        userId: userId,
        itemUuid: itemUuid,
        fallbackFileName: invoiceFileName,
        fallbackSizeBytes: invoiceFileSizeBytes,
      );
    }

    final resolvedFileName =
        _resolvedFileName(trimmedPath, fallback: invoiceFileName);

    // ── PDF optimization: validate size + attempt compression ────────────
    File fileToUpload = localFile;
    int fileSize = invoiceFileSizeBytes ?? await localFile.length();
    String originalFileNameResolved = resolvedFileName;
    int originalFileSizeBytesResolved = fileSize;
    String mimeType = _contentTypeFor(resolvedFileName);
    bool compressionApplied = false;

    if (_pdfOptimizer.isPdf(resolvedFileName)) {
      debugPrint('[IkeepInvoice] PDF detected — running optimizer...');
      // Throws PdfTooLargeException if file exceeds hard limit.
      final pdfResult = await _pdfOptimizer.optimizeForUpload(
        trimmedPath,
        originalFileName: resolvedFileName,
      );
      fileToUpload = pdfResult.file;
      fileSize = pdfResult.optimizedFileSizeBytes;
      originalFileNameResolved = pdfResult.originalFileName;
      originalFileSizeBytesResolved = pdfResult.originalFileSizeBytes;
      mimeType = pdfResult.mimeType;
      compressionApplied = pdfResult.compressionApplied;

      debugPrint(
        '[IkeepInvoice] PDF optimizer done: '
        'original=${pdfResult.originalFileSizeBytes} bytes '
        'final=$fileSize bytes '
        'compressed=$compressionApplied',
      );
    }

    final extension = p.extension(resolvedFileName);
    final storageObjectPath =
        '${_invoiceFolder(userId, itemUuid)}/invoice${extension.isEmpty ? '' : extension}';
    final ref = _storage.ref().child(storageObjectPath);

    debugPrint(
      '[IkeepInvoice] Uploading invoice: fileName=$resolvedFileName '
      'size=$fileSize bytes → $storageObjectPath',
    );

    await ref.putFile(
      fileToUpload,
      SettableMetadata(
        contentType: mimeType,
        cacheControl: 'public,max-age=31536000',
        customMetadata: {
          'originalFileName': originalFileNameResolved,
          'sourceBytes': originalFileSizeBytesResolved.toString(),
          'uploadedBytes': fileSize.toString(),
          'compressionApplied': compressionApplied.toString(),
        },
      ),
    ).timeout(_putFileTimeout, onTimeout: () {
      throw TimeoutException(
        'Invoice putFile timed out after ${_putFileTimeout.inSeconds}s '
        'for $itemUuid',
      );
    });
    debugPrint('[IkeepInvoice] Invoice putFile SUCCESS → fetching download URL');

    await _pruneUnexpectedInvoices(
      userId: userId,
      itemUuid: itemUuid,
      keepStoragePath: ref.fullPath,
    );

    final downloadUrl = await ref.getDownloadURL().timeout(_getUrlTimeout);
    debugPrint('[IkeepInvoice] Invoice download URL received');

    return StoredInvoiceFile(
      path: downloadUrl,
      fileName: resolvedFileName,
      sizeBytes: fileSize,
      storagePath: ref.fullPath,
      originalFileName: originalFileNameResolved,
      originalFileSizeBytes: originalFileSizeBytesResolved,
      mimeType: mimeType,
      compressionApplied: compressionApplied,
    );
  }

  /// Resolves an invoice from a cloud-restore record into a usable
  /// [StoredInvoiceFile].
  ///
  /// Resolution order:
  /// 1. If [storagePath] is provided (new backup format), call
  ///    [getDownloadURL()] on it for a guaranteed-fresh URL.
  /// 2. Else if [invoicePath] is a valid remote path, use it directly.
  /// 3. Fall back to listing the item's invoice folder in Storage.
  Future<StoredInvoiceFile?> resolveCloudInvoice({
    required String userId,
    required String itemUuid,
    String? invoicePath,
    String? invoiceFileName,
    int? invoiceFileSizeBytes,
    String? storagePath, // durable Storage object path (new)
  }) async {
    // ── Primary: use durable storage path for a fresh download URL ──────────
    if (storagePath != null && storagePath.trim().isNotEmpty) {
      try {
        final ref = storagePath.toLowerCase().startsWith('gs://')
            ? _storage.refFromURL(storagePath)
            : _storage.ref().child(storagePath);
        final freshUrl = await ref.getDownloadURL().timeout(_getUrlTimeout);
        final metadata = await ref.getMetadata().timeout(_getMetadataTimeout);
        final name = invoiceFileName?.trim().isNotEmpty == true
            ? invoiceFileName!.trim()
            : metadata.customMetadata?['originalFileName'] ??
                p.basename(storagePath);
        return StoredInvoiceFile(
          path: freshUrl,
          fileName: name,
          sizeBytes: invoiceFileSizeBytes ?? metadata.size,
          storagePath: ref.fullPath,
        );
      } catch (e) {
        if (!_isMissingObjectError(e)) {
          // Unexpected error — log but continue to fallbacks.
          rethrow;
        }
        // Storage object gone — fall through to other fallbacks.
      }
    }

    // ── Fallback 1: use the stored download/remote URL ────────────────────────
    final trimmedPath = invoicePath?.trim() ?? '';
    if (trimmedPath.isNotEmpty) {
      final resolvedPath = await _resolveRemotePath(trimmedPath);
      if (resolvedPath != null) {
        return StoredInvoiceFile(
          path: resolvedPath,
          fileName: _resolvedFileName(trimmedPath, fallback: invoiceFileName),
          sizeBytes: invoiceFileSizeBytes,
          storagePath: _tryResolveStoragePath(trimmedPath),
        );
      }
    }

    // ── Fallback 2: list the item's invoice folder ────────────────────────────
    return _getStoredInvoice(
      userId: userId,
      itemUuid: itemUuid,
      fallbackFileName: invoiceFileName,
      fallbackSizeBytes: invoiceFileSizeBytes,
    );
  }

  Future<void> deleteItemInvoice({
    required String userId,
    required String itemUuid,
  }) async {
    try {
      final folder = _storage.ref().child(_invoiceFolder(userId, itemUuid));
      final list = await folder.listAll().timeout(_listAllTimeout);
      await Future.wait(list.items.map((ref) async {
        try {
          await ref.delete();
        } catch (error) {
          if (!_isMissingObjectError(error)) rethrow;
        }
      }));
    } catch (error) {
      if (!_isMissingObjectError(error)) rethrow;
    }
  }

  Future<void> _pruneUnexpectedInvoices({
    required String userId,
    required String itemUuid,
    required String keepStoragePath,
  }) async {
    try {
      final folder = _storage.ref().child(_invoiceFolder(userId, itemUuid));
      final list = await folder.listAll().timeout(_listAllTimeout);
      final staleRefs = list.items
          .where((ref) => ref.fullPath != keepStoragePath)
          .toList(growable: false);
      await Future.wait(staleRefs.map((ref) async {
        try {
          await ref.delete();
        } catch (error) {
          if (!_isMissingObjectError(error)) rethrow;
        }
      }));
    } catch (error) {
      if (!_isMissingObjectError(error)) rethrow;
    }
  }

  Future<StoredInvoiceFile?> _getStoredInvoice({
    required String userId,
    required String itemUuid,
    String? fallbackFileName,
    int? fallbackSizeBytes,
  }) async {
    try {
      final folder = _storage.ref().child(_invoiceFolder(userId, itemUuid));
      final list = await folder.listAll();
      if (list.items.isEmpty) return null;

      final refs = [...list.items]
        ..sort((a, b) => a.fullPath.compareTo(b.fullPath));
      final ref = refs.first;
      final metadata = await ref.getMetadata().timeout(_getMetadataTimeout);
      return StoredInvoiceFile(
        path: await ref.getDownloadURL().timeout(_getUrlTimeout),
        fileName: fallbackFileName?.trim().isNotEmpty == true
            ? fallbackFileName!.trim()
            : metadata.customMetadata?['originalFileName'] ??
                p.basename(ref.fullPath),
        sizeBytes: fallbackSizeBytes ?? metadata.size,
        storagePath: ref.fullPath, // ← always include durable path
      );
    } catch (error) {
      if (_isMissingObjectError(error)) {
        return null;
      }
      rethrow;
    }
  }

  Future<String?> _resolveRemotePath(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (normalized.toLowerCase().startsWith('http://') ||
        normalized.toLowerCase().startsWith('https://')) {
      return normalized;
    }

    try {
      if (normalized.toLowerCase().startsWith('gs://')) {
        return await _storage
            .refFromURL(normalized)
            .getDownloadURL()
            .timeout(_getUrlTimeout);
      }
      if (normalized.contains('/')) {
        return await _storage
            .ref()
            .child(normalized)
            .getDownloadURL()
            .timeout(_getUrlTimeout);
      }
    } catch (error) {
      if (_isMissingObjectError(error)) {
        return null;
      }
      rethrow;
    }

    return null;
  }

  /// Attempts to extract the Firebase Storage object path from a URL.
  /// Returns null if the URL is not a Firebase Storage URL.
  String? _tryResolveStoragePath(String url) {
    try {
      return _storage.refFromURL(url).fullPath;
    } catch (_) {
      return null;
    }
  }

  String _invoiceFolder(String userId, String itemUuid) {
    return '${StorageConstants.firebaseItemImagesRoot}/$userId/items/$itemUuid/invoices';
  }

  String _resolvedFileName(String path, {String? fallback}) {
    final trimmedFallback = fallback?.trim();
    if (trimmedFallback != null && trimmedFallback.isNotEmpty) {
      return trimmedFallback;
    }

    final parsed = Uri.tryParse(path);
    if (parsed != null && parsed.pathSegments.isNotEmpty) {
      final last = parsed.pathSegments.last.trim();
      if (last.isNotEmpty) return last;
    }

    final localName = p.basename(path);
    if (localName.trim().isNotEmpty) {
      return localName.trim();
    }

    return 'invoice';
  }

  String _contentTypeFor(String fileName) {
    switch (p.extension(fileName).toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  bool _isMissingObjectError(dynamic error) {
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('object-not-found') ||
        normalized.contains('no object exists') ||
        normalized.contains('not-found')) {
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
