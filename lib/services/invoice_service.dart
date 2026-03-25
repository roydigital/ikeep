import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/storage_constants.dart';
import '../core/utils/path_utils.dart';

class PickedInvoiceFile {
  const PickedInvoiceFile({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
  });

  final String path;
  final String fileName;
  final int sizeBytes;
}

class InvoiceService {
  static const MethodChannel _nativeInvoicePickerChannel =
      MethodChannel('ikeep/native_invoice_picker');

  Future<bool> openInvoice(String invoicePath) async {
    final trimmedPath = invoicePath.trim();
    if (trimmedPath.isEmpty) return false;

    if (PathUtils.isRemotePath(trimmedPath)) {
      final uri = Uri.tryParse(trimmedPath);
      if (uri == null) return false;
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    final file = File(trimmedPath);
    if (!await file.exists()) {
      return false;
    }

    if (Platform.isAndroid) {
      try {
        final opened = await _nativeInvoicePickerChannel.invokeMethod<bool>(
          'openInvoice',
          {'path': file.path},
        );
        return opened ?? false;
      } on MissingPluginException catch (error) {
        debugPrint('InvoiceService.openInvoice missing native channel: $error');
        return false;
      } on PlatformException catch (error) {
        debugPrint(
          'InvoiceService.openInvoice native open failed: '
          '${error.code} ${error.message}',
        );
        return false;
      }
    }

    return launchUrl(
      Uri.file(file.path),
      mode: LaunchMode.platformDefault,
    );
  }

  Future<Directory> _invoicesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(appDir.path, StorageConstants.itemInvoicesDir),
    );
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<PickedInvoiceFile?> pickInvoice() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        withData: false,
        withReadStream: true,
        dialogTitle: 'Select invoice',
      );

      if (result == null || result.files.isEmpty) return null;

      final picked = result.files.single;
      final originalName = picked.name.trim().isNotEmpty
          ? picked.name.trim()
          : (picked.path?.trim().isNotEmpty == true
              ? p.basename(picked.path!)
              : 'invoice');
      final ext = p.extension(originalName);
      final baseName = p.basenameWithoutExtension(originalName);
      final safeBaseName = _sanitizeName(baseName);
      final targetName =
          '${DateTime.now().millisecondsSinceEpoch}_${safeBaseName.isEmpty ? 'invoice' : safeBaseName}$ext';

      final dir = await _invoicesDir();
      final targetPath = p.join(dir.path, targetName);
      await _savePickedFile(picked, targetPath);

      final savedFile = File(targetPath);
      final stat = await savedFile.stat();
      return PickedInvoiceFile(
        path: targetPath,
        fileName: originalName,
        sizeBytes: stat.size,
      );
    } on MissingPluginException {
      return _pickInvoiceWithNativeAndroidFallback();
    } on PlatformException catch (error) {
      if (!_shouldUseNativeAndroidFallback(error)) {
        rethrow;
      }
      return _pickInvoiceWithNativeAndroidFallback();
    }
  }

  Future<void> _savePickedFile(PlatformFile picked, String targetPath) async {
    final sourcePath = picked.path?.trim();
    if (sourcePath != null && sourcePath.isNotEmpty) {
      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) {
        await sourceFile.copy(targetPath);
        return;
      }
    }

    final readStream = picked.readStream;
    if (readStream != null) {
      final outputFile = File(targetPath);
      final sink = outputFile.openWrite();
      try {
        await sink.addStream(readStream);
      } finally {
        await sink.close();
      }
      return;
    }

    throw const FileSystemException(
      'Selected invoice could not be read from the picker',
    );
  }

  Future<void> deleteInvoice(String invoicePath) async {
    final trimmedPath = invoicePath.trim();
    if (trimmedPath.isEmpty) return;

    final file = File(trimmedPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _sanitizeName(String value) {
    return value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<PickedInvoiceFile?> _pickInvoiceWithNativeAndroidFallback() async {
    if (!Platform.isAndroid) {
      throw MissingPluginException(
        'Native invoice picker fallback is only available on Android',
      );
    }

    final result = await _nativeInvoicePickerChannel
        .invokeMapMethod<String, dynamic>('pickInvoice');
    if (result == null) return null;

    final targetPath = (result['path'] as String? ?? '').trim();
    if (targetPath.isEmpty) {
      throw const FileSystemException(
        'Native invoice picker did not return a file path',
      );
    }

    final file = File(targetPath);
    final exists = await file.exists();
    if (!exists) {
      throw FileSystemException(
        'Native invoice picker returned a missing file',
        targetPath,
      );
    }

    final returnedName = (result['fileName'] as String? ?? '').trim();
    final stat = await file.stat();
    return PickedInvoiceFile(
      path: targetPath,
      fileName: returnedName.isNotEmpty ? returnedName : p.basename(targetPath),
      sizeBytes: (result['sizeBytes'] as num?)?.toInt() ?? stat.size,
    );
  }

  bool _shouldUseNativeAndroidFallback(PlatformException error) {
    if (!Platform.isAndroid) return false;

    final errorText = [
      error.code,
      error.message,
      '${error.details}',
    ].join(' ').toLowerCase();

    return errorText.contains('method not found') ||
        errorText.contains('missingpluginexception') ||
        errorText.contains('unsupported operation') ||
        error.code == 'channel-error';
  }
}
