import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import '../domain/models/ml_label.dart';

/// Wraps Google ML Kit image labeling to provide on-device item name suggestions.
/// Labels are ephemeral — they are never stored by this service.
class MlLabelService {
  ImageLabeler? _labeler;

  ImageLabeler _getLabeler() {
    _labeler ??= ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.5),
    );
    return _labeler!;
  }

  /// Returns ML label suggestions for the image at [imagePath].
  /// Returns an empty list if ML Kit is unavailable or the image fails to process.
  Future<List<MlLabel>> getLabelsForImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final labels = await _getLabeler().processImage(inputImage);
      return labels
          .map((l) => MlLabel(label: l.label, confidence: l.confidence))
          .toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
    } catch (e) {
      // Gracefully degrade — ML Kit may not work on all platforms/emulators.
      debugPrint('MlLabelService: failed to label image — $e');
      return [];
    }
  }

  Future<void> dispose() async {
    await _labeler?.close();
    _labeler = null;
  }
}
