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

  Future<String> classifySeasonCategory({
    required String itemName,
    List<String> tags = const [],
    List<String> imagePaths = const [],
  }) async {
    final tokens = <String>[
      itemName.toLowerCase(),
      ...tags.map((tag) => tag.toLowerCase()),
    ];

    if (imagePaths.isNotEmpty) {
      final labels = await getLabelsForImage(imagePaths.first);
      tokens.addAll(labels.take(5).map((label) => label.label.toLowerCase()));
    }

    final haystack = tokens.join(' ');
    final scores = <String, int>{
      'winter': _scoreForKeywords(haystack, _winterKeywords),
      'summer': _scoreForKeywords(haystack, _summerKeywords),
      'holiday': _scoreForKeywords(haystack, _holidayKeywords),
    };

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (ranked.isEmpty || ranked.first.value == 0) {
      return 'all_year';
    }

    return ranked.first.key;
  }

  int _scoreForKeywords(String haystack, List<String> keywords) {
    return keywords.where(haystack.contains).length;
  }

  static const List<String> _winterKeywords = [
    'coat',
    'jacket',
    'sweater',
    'hoodie',
    'blanket',
    'heater',
    'boots',
    'gloves',
    'thermal',
    'ski',
    'snow',
    'winter',
  ];

  static const List<String> _summerKeywords = [
    'summer',
    'beach',
    'swim',
    'swimsuit',
    'sunscreen',
    'fan',
    'shorts',
    'sandals',
    'sunglasses',
    'cooler',
    'vacation',
  ];

  static const List<String> _holidayKeywords = [
    'holiday',
    'christmas',
    'xmas',
    'ornament',
    'tree',
    'lights',
    'wreath',
    'stocking',
    'gift',
    'festive',
    'decoration',
  ];

  Future<void> dispose() async {
    await _labeler?.close();
    _labeler = null;
  }
}
