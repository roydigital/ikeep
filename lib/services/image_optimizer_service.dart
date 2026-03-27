import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/feature_limits.dart';
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

class OptimizedImageBundle {
  const OptimizedImageBundle({
    required this.fullImage,
    this.thumbnail,
  });

  final OptimizedImageResult fullImage;
  final OptimizedImageResult? thumbnail;
}

class ImageTooLargeException implements Exception {
  const ImageTooLargeException({
    required this.path,
    required this.byteSize,
    required this.maxBytes,
  });

  final String path;
  final int byteSize;
  final int maxBytes;

  @override
  String toString() {
    return 'ImageTooLargeException(path: $path, byteSize: $byteSize, maxBytes: $maxBytes)';
  }
}

class ImageOptimizerService {
  ImageOptimizerService();

  String get preferredUploadExtension => _extensionFor(_preferredFormat());

  String get preferredContentType => _contentTypeFor(_preferredFormat());

  static const int _maxOptimizationPasses = 6;
  static const int _qualityStep = 6;
  static const int _dimensionStepPx = 96;
  static const int _minFullImageDimensionPx = 768;
  static const int _minThumbnailDimensionPx = 120;
  static const int _minFullImageQuality = 50;
  static const int _minThumbnailQuality = 42;

  Future<OptimizedImageBundle> optimizeForCloudUpload(String inputPath) async {
    final fullImage = await optimizeForUpload(
      inputPath,
      maxDimension: maxFullImageDimensionPx,
      quality: fullImageUploadQuality,
      targetBytes: targetFullImageBytes,
      maxBytes: maxFullImageBytes,
    );

    OptimizedImageResult? thumbnail;
    try {
      thumbnail = await optimizeThumbnailForUpload(inputPath);
    } catch (error) {
      debugPrint(
        '[IkeepImage] Thumbnail optimization failed for $inputPath: $error',
      );
    }

    return OptimizedImageBundle(
      fullImage: fullImage,
      thumbnail: thumbnail,
    );
  }

  Future<OptimizedImageResult> optimizeForUpload(
    String inputPath, {
    int maxDimension = AppConstants.uploadImageMaxDimension,
    int quality = AppConstants.uploadImageQuality,
    int targetBytes = AppConstants.uploadImageTargetBytes,
    int maxBytes = maxFullImageBytes,
  }) async {
    return _optimize(
      inputPath,
      maxDimension: maxDimension,
      quality: quality,
      targetBytes: targetBytes,
      maxBytes: maxBytes,
      minDimension: _minFullImageDimensionPx,
      minQuality: _minFullImageQuality,
    );
  }

  Future<OptimizedImageResult> optimizeThumbnailForUpload(
    String inputPath, {
    int maxDimension = thumbnailMaxDimensionPx,
    int quality = thumbnailUploadQuality,
    int targetBytes = targetThumbnailBytes,
    int maxBytes = maxThumbnailBytes,
  }) async {
    return _optimize(
      inputPath,
      maxDimension: maxDimension,
      quality: quality,
      targetBytes: targetBytes,
      maxBytes: maxBytes,
      minDimension: _minThumbnailDimensionPx,
      minQuality: _minThumbnailQuality,
      fileNameSuffix: StorageConstants.firebaseThumbnailSuffix,
    );
  }

  Future<OptimizedImageResult> _optimize(
    String inputPath, {
    required int maxDimension,
    required int quality,
    required int targetBytes,
    required int maxBytes,
    required int minDimension,
    required int minQuality,
    String fileNameSuffix = '',
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
    File? bestFile;
    int? bestBytes;

    for (final attempt in _buildAttempts(
      maxDimension: maxDimension,
      quality: quality,
      minDimension: minDimension,
      minQuality: minQuality,
    )) {
      final candidate = await _compress(
        sourcePath: inputPath,
        directory: optimizedDir.path,
        format: format,
        maxDimension: attempt.maxDimension,
        quality: attempt.quality,
        fileNameSuffix: fileNameSuffix,
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

      if (bytes <= targetBytes) {
        break;
      }
    }

    if (bestFile == null || bestBytes == null) {
      throw StateError('Image optimization failed for $inputPath');
    }

    if (bestBytes > maxBytes) {
      await _safeDelete(bestFile);
      throw ImageTooLargeException(
        path: inputPath,
        byteSize: bestBytes,
        maxBytes: maxBytes,
      );
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
    String fileNameSuffix = '',
  }) async {
    final extension = _extensionFor(format);
    final targetPath = p.join(
      directory,
      '${DateTime.now().microsecondsSinceEpoch}_${quality}_$maxDimension$fileNameSuffix$extension',
    );

    final output = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      targetPath,
      minWidth: maxDimension,
      minHeight: maxDimension,
      quality: quality,
      format: format,
      keepExif: false,
      autoCorrectionAngle: true,
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

  List<_OptimizationAttempt> _buildAttempts({
    required int maxDimension,
    required int quality,
    required int minDimension,
    required int minQuality,
  }) {
    final attempts = <_OptimizationAttempt>[];

    for (var pass = 0; pass < _maxOptimizationPasses; pass++) {
      final dimension =
          (maxDimension - (pass * _dimensionStepPx)).clamp(minDimension, maxDimension);
      final nextQuality =
          (quality - (pass * _qualityStep)).clamp(minQuality, quality);
      final attempt = _OptimizationAttempt(
        maxDimension: dimension.toInt(),
        quality: nextQuality.toInt(),
      );

      if (attempts.any(
        (existing) =>
            existing.maxDimension == attempt.maxDimension &&
            existing.quality == attempt.quality,
      )) {
        continue;
      }
      attempts.add(attempt);
    }

    return attempts;
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
