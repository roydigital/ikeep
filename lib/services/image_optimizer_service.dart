import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/storage_constants.dart';
import '../core/utils/path_utils.dart';

class OptimizedImageResult {
  const OptimizedImageResult({
    required this.file,
    required this.contentType,
    required this.extension,
    required this.byteSize,
  });

  final File file;
  final String contentType;
  final String extension;
  final int byteSize;
}

class ImageOptimizerService {
  ImageOptimizerService();

  String get preferredUploadExtension => _extensionFor(_preferredFormat());

  String get preferredContentType => _contentTypeFor(_preferredFormat());

  Future<OptimizedImageResult> optimizeForUpload(
    String inputPath, {
    int maxDimension = AppConstants.uploadImageMaxDimension,
    int quality = AppConstants.uploadImageQuality,
    int targetBytes = AppConstants.uploadImageTargetBytes,
  }) async {
    if (PathUtils.isRemotePath(inputPath)) {
      throw ArgumentError.value(
        inputPath,
        'inputPath',
        'Remote URLs cannot be optimized locally.',
      );
    }

    final sourceFile = File(inputPath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Image file not found', inputPath);
    }

    final tempDir = await getTemporaryDirectory();
    final optimizedDir = Directory(
      p.join(tempDir.path, StorageConstants.optimizedUploadsDir),
    );
    if (!optimizedDir.existsSync()) {
      await optimizedDir.create(recursive: true);
    }

    final format = _preferredFormat();

    // Try the highest quality first. Only attempt more aggressive compression
    // if the result exceeds the target byte size. This avoids wasting CPU
    // cycles on images that are already small enough.
    final firstPass = await _compress(
      sourcePath: inputPath,
      directory: optimizedDir.path,
      format: format,
      maxDimension: maxDimension,
      quality: quality,
    );
    if (firstPass != null) {
      final bytes = await firstPass.length();
      if (bytes <= targetBytes) {
        return OptimizedImageResult(
          file: firstPass,
          contentType: _contentTypeFor(format),
          extension: _extensionFor(format),
          byteSize: bytes,
        );
      }
    }

    // First pass was too large (or failed) — try progressively smaller.
    final fallbackAttempts = <_OptimizationAttempt>[
      _OptimizationAttempt(
        maxDimension: maxDimension,
        quality: quality >= 74 ? 74 : quality,
      ),
      _OptimizationAttempt(
        maxDimension: maxDimension >= 1080 ? 1080 : maxDimension,
        quality: 70,
      ),
      _OptimizationAttempt(
        maxDimension: maxDimension >= 960 ? 960 : maxDimension,
        quality: 64,
      ),
    ];

    File? bestFile = firstPass;
    int? bestBytes = firstPass != null ? await firstPass.length() : null;

    for (final attempt in fallbackAttempts) {
      final candidate = await _compress(
        sourcePath: inputPath,
        directory: optimizedDir.path,
        format: format,
        maxDimension: attempt.maxDimension,
        quality: attempt.quality,
      );
      if (candidate == null) continue;

      final bytes = await candidate.length();
      if (bestBytes == null || bytes < bestBytes) {
        if (bestFile != null && bestFile.path != candidate.path) {
          await _safeDelete(bestFile);
        }
        bestFile = candidate;
        bestBytes = bytes;
      } else {
        await _safeDelete(candidate);
      }

      if (bytes <= targetBytes) break;
    }

    if (bestFile == null || bestBytes == null) {
      throw StateError('Image optimization failed for $inputPath');
    }

    return OptimizedImageResult(
      file: bestFile,
      contentType: _contentTypeFor(format),
      extension: _extensionFor(format),
      byteSize: bestBytes,
    );
  }

  Future<File?> _compress({
    required String sourcePath,
    required String directory,
    required CompressFormat format,
    required int maxDimension,
    required int quality,
  }) async {
    final extension = _extensionFor(format);
    final targetPath = p.join(
      directory,
      '${DateTime.now().microsecondsSinceEpoch}_${quality}_$maxDimension$extension',
    );

    final output = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      targetPath,
      minWidth: maxDimension,
      minHeight: maxDimension,
      quality: quality,
      format: format,
      keepExif: false,
    );

    if (output == null) return null;
    return File(output.path);
  }

  CompressFormat _preferredFormat() {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return CompressFormat.webp;
    }
    return CompressFormat.jpeg;
  }

  String _contentTypeFor(CompressFormat format) {
    switch (format) {
      case CompressFormat.webp:
        return 'image/webp';
      case CompressFormat.jpeg:
      default:
        return 'image/jpeg';
    }
  }

  String _extensionFor(CompressFormat format) {
    switch (format) {
      case CompressFormat.webp:
        return '.webp';
      case CompressFormat.jpeg:
      default:
        return '.jpg';
    }
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup for temporary optimized files.
    }
  }
}

class _OptimizationAttempt {
  const _OptimizationAttempt({
    required this.maxDimension,
    required this.quality,
  });

  final int maxDimension;
  final int quality;
}
