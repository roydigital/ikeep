import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

import '../core/constants/storage_constants.dart';
import '../core/utils/path_utils.dart';

class StoredInvoiceFile {
  const StoredInvoiceFile({
    required this.path,
    required this.fileName,
    this.sizeBytes,
  });

  final String path;
  final String fileName;
  final int? sizeBytes;
}

class FirebaseInvoiceStorageService {
  FirebaseInvoiceStorageService({
    required FirebaseStorage storage,
  }) : _storage = storage;

  final FirebaseStorage _storage;

  Future<StoredInvoiceFile?> uploadItemInvoice({
    required String userId,
    required String itemUuid,
    required String? invoicePath,
    String? invoiceFileName,
    int? invoiceFileSizeBytes,
  }) async {
    final trimmedPath = invoicePath?.trim() ?? '';
    if (trimmedPath.isEmpty) {
      await deleteItemInvoice(userId: userId, itemUuid: itemUuid);
      return null;
    }

    if (PathUtils.isRemotePath(trimmedPath)) {
      return StoredInvoiceFile(
        path: trimmedPath,
        fileName: _resolvedFileName(trimmedPath, fallback: invoiceFileName),
        sizeBytes: invoiceFileSizeBytes,
      );
    }

    final localFile = File(trimmedPath);
    if (!await localFile.exists()) {
      return _getStoredInvoice(
        userId: userId,
        itemUuid: itemUuid,
        fallbackFileName: invoiceFileName,
        fallbackSizeBytes: invoiceFileSizeBytes,
      );
    }

    final resolvedFileName =
        _resolvedFileName(trimmedPath, fallback: invoiceFileName);
    final extension = p.extension(resolvedFileName);
    final storagePath =
        '${_invoiceFolder(userId, itemUuid)}/invoice${extension.isEmpty ? '' : extension}';
    final ref = _storage.ref().child(storagePath);
    final fileSize = invoiceFileSizeBytes ?? await localFile.length();

    await ref.putFile(
      localFile,
      SettableMetadata(
        contentType: _contentTypeFor(resolvedFileName),
        cacheControl: 'public,max-age=31536000',
        customMetadata: {
          'originalFileName': resolvedFileName,
          'sourceBytes': fileSize.toString(),
        },
      ),
    );

    await _pruneUnexpectedInvoices(
      userId: userId,
      itemUuid: itemUuid,
      keepStoragePath: ref.fullPath,
    );

    return StoredInvoiceFile(
      path: await ref.getDownloadURL(),
      fileName: resolvedFileName,
      sizeBytes: fileSize,
    );
  }

  Future<StoredInvoiceFile?> resolveCloudInvoice({
    required String userId,
    required String itemUuid,
    String? invoicePath,
    String? invoiceFileName,
    int? invoiceFileSizeBytes,
  }) async {
    final trimmedPath = invoicePath?.trim() ?? '';
    if (trimmedPath.isNotEmpty) {
      final resolvedPath = await _resolveRemotePath(trimmedPath);
      if (resolvedPath != null) {
        return StoredInvoiceFile(
          path: resolvedPath,
          fileName: _resolvedFileName(trimmedPath, fallback: invoiceFileName),
          sizeBytes: invoiceFileSizeBytes,
        );
      }
    }

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
      final list = await folder.listAll();
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
      final list = await folder.listAll();
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
      final metadata = await ref.getMetadata();
      return StoredInvoiceFile(
        path: await ref.getDownloadURL(),
        fileName: fallbackFileName?.trim().isNotEmpty == true
            ? fallbackFileName!.trim()
            : metadata.customMetadata?['originalFileName'] ??
                p.basename(ref.fullPath),
        sizeBytes: fallbackSizeBytes ?? metadata.size,
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
        return await _storage.refFromURL(normalized).getDownloadURL();
      }
      if (normalized.contains('/')) {
        return await _storage.ref().child(normalized).getDownloadURL();
      }
    } catch (error) {
      if (_isMissingObjectError(error)) {
        return null;
      }
      rethrow;
    }

    return null;
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
