import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/constants/feature_limits.dart';

/// Thrown when a PDF exceeds the hard size limit after all optimization
/// attempts have been exhausted.
class PdfTooLargeException implements Exception {
  const PdfTooLargeException(this.message, {required this.fileSizeBytes});

  final String message;
  final int fileSizeBytes;

  @override
  String toString() => 'PdfTooLargeException: $message ($fileSizeBytes bytes)';
}

/// The outcome of running a PDF through the optimization pipeline.
class PdfOptimizationResult {
  const PdfOptimizationResult({
    required this.file,
    required this.originalFileName,
    required this.optimizedFileName,
    required this.originalFileSizeBytes,
    required this.optimizedFileSizeBytes,
    required this.mimeType,
    required this.compressionApplied,
  });

  /// The file to upload (may be the original if no compression was needed).
  final File file;

  /// Name of the file the user originally selected.
  final String originalFileName;

  /// Name of the file that will actually be uploaded.
  final String optimizedFileName;

  /// Size of the original file in bytes.
  final int originalFileSizeBytes;

  /// Size of the optimized file in bytes (equals [originalFileSizeBytes] when
  /// no compression was applied).
  final int optimizedFileSizeBytes;

  /// MIME type of the file (always `application/pdf` for PDFs).
  final String mimeType;

  /// Whether any compression/optimization was actually applied.
  final bool compressionApplied;

  /// How much smaller the optimized file is compared to the original.
  double get savingsPercent {
    if (originalFileSizeBytes == 0) return 0;
    return ((originalFileSizeBytes - optimizedFileSizeBytes) /
            originalFileSizeBytes) *
        100;
  }
}

/// Handles PDF size validation and optimization before Firebase upload.
///
/// Current strategy (stable, no external PDF library):
///   1. If file size <= soft limit → pass through unchanged.
///   2. If file size > soft limit → attempt optimization (currently a
///      pass-through stub — extend when a reliable PDF compression package
///      becomes available).
///   3. If final size > hard limit → throw [PdfTooLargeException].
///
/// The service is designed so that a real compression step can be plugged in
/// at [_tryCompressPdf] without changing the public API.
class PdfOptimizerService {
  /// Validates and optionally optimizes a local PDF file for upload.
  ///
  /// Returns a [PdfOptimizationResult] with metadata about the original and
  /// final file. Throws [PdfTooLargeException] if the file exceeds the hard
  /// limit after all optimization attempts.
  Future<PdfOptimizationResult> optimizeForUpload(
    String inputPath, {
    String? originalFileName,
  }) async {
    final sourceFile = File(inputPath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('PDF file not found', inputPath);
    }

    final resolvedOriginalName =
        originalFileName?.trim().isNotEmpty == true
            ? originalFileName!.trim()
            : p.basename(inputPath);
    final originalSize = await sourceFile.length();

    debugPrint(
      '[IkeepPdf] optimizeForUpload: file=$resolvedOriginalName '
      'size=$originalSize bytes '
      '(softLimit=$pdfSoftLimitBytes hardLimit=$pdfHardLimitBytes)',
    );

    // ── Fast path: file is small enough — no optimization needed ──────────
    if (originalSize <= pdfSoftLimitBytes) {
      debugPrint(
        '[IkeepPdf] PDF is within soft limit ($pdfSoftLimitLabel) — '
        'uploading directly',
      );
      return PdfOptimizationResult(
        file: sourceFile,
        originalFileName: resolvedOriginalName,
        optimizedFileName: resolvedOriginalName,
        originalFileSizeBytes: originalSize,
        optimizedFileSizeBytes: originalSize,
        mimeType: 'application/pdf',
        compressionApplied: false,
      );
    }

    // ── File exceeds soft limit — attempt optimization ────────────────────
    debugPrint(
      '[IkeepPdf] PDF exceeds soft limit ($pdfSoftLimitLabel) — '
      'attempting optimization...',
    );

    final optimized = await _tryCompressPdf(sourceFile, resolvedOriginalName);
    final optimizedFile = optimized?.file ?? sourceFile;
    final optimizedSize = optimized?.sizeBytes ?? originalSize;
    final wasCompressed = optimized != null && optimized.sizeBytes < originalSize;

    if (wasCompressed) {
      debugPrint(
        '[IkeepPdf] Optimization result: '
        '$originalSize -> $optimizedSize bytes '
        '(saved ${((originalSize - optimizedSize) / originalSize * 100).toStringAsFixed(1)}%)',
      );
    } else {
      debugPrint(
        '[IkeepPdf] No effective compression available — '
        'proceeding with original file ($originalSize bytes)',
      );
    }

    // ── Post-optimization hard limit check ────────────────────────────────
    if (optimizedSize > pdfHardLimitBytes) {
      debugPrint(
        '[IkeepPdf] REJECTED: PDF is $optimizedSize bytes, '
        'exceeds hard limit ($pdfHardLimitLabel)',
      );

      // Clean up temp optimized file if we created one.
      if (wasCompressed) {
        await _safeDelete(optimizedFile);
      }

      throw PdfTooLargeException(
        wasCompressed
            ? pdfSizeAfterOptimizationError()
            : pdfHardLimitExceededError(),
        fileSizeBytes: optimizedSize,
      );
    }

    final optimizedName = wasCompressed
        ? 'opt_$resolvedOriginalName'
        : resolvedOriginalName;

    debugPrint(
      '[IkeepPdf] Final PDF ready for upload: '
      'name=$optimizedName size=$optimizedSize bytes '
      'compressed=$wasCompressed',
    );

    return PdfOptimizationResult(
      file: optimizedFile,
      originalFileName: resolvedOriginalName,
      optimizedFileName: optimizedName,
      originalFileSizeBytes: originalSize,
      optimizedFileSizeBytes: optimizedSize,
      mimeType: 'application/pdf',
      compressionApplied: wasCompressed,
    );
  }

  /// Whether the given file path points to a PDF.
  bool isPdf(String filePath) {
    return p.extension(filePath).toLowerCase() == '.pdf';
  }

  /// Whether the given file size exceeds the hard limit.
  bool exceedsHardLimit(int sizeBytes) => sizeBytes > pdfHardLimitBytes;

  /// Attempts to compress the PDF and return a smaller version.
  ///
  /// Currently returns `null` (no compression available). When a reliable
  /// PDF compression library is added, implement this method to:
  ///   1. Strip unused metadata, fonts, and embedded resources.
  ///   2. Downsample embedded images.
  ///   3. Re-linearize the PDF structure.
  ///
  /// The returned file should be a temp file that the caller will clean up.
  Future<_CompressedPdf?> _tryCompressPdf(
    File sourceFile,
    String fileName,
  ) async {
    // ── Stub: no PDF compression library available yet ────────────────────
    // To add compression later, replace this with a call to a PDF library
    // such as syncfusion_flutter_pdf or a native Android method channel.
    //
    // Example future implementation:
    //   final tempDir = await getTemporaryDirectory();
    //   final tempPath = p.join(tempDir.path, 'opt_$fileName');
    //   final compressed = await PdfCompressor.compress(sourceFile, tempPath);
    //   return _CompressedPdf(file: File(tempPath), sizeBytes: compressed.size);
    return null;
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup for temporary files.
    }
  }
}

class _CompressedPdf {
  const _CompressedPdf({required this.file, required this.sizeBytes});
  final File file;
  final int sizeBytes;
}
