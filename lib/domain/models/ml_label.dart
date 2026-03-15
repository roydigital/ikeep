/// A label suggestion returned by the on-device ML image labeling service.
/// These are ephemeral — never persisted. Used only in the save flow UI.
class MlLabel {
  const MlLabel({
    required this.label,
    required this.confidence,
  });

  final String label;

  /// Confidence score between 0.0 and 1.0.
  final double confidence;

  /// Returns true if confidence is high enough to show as a primary suggestion.
  bool get isHighConfidence => confidence >= 0.75;

  @override
  String toString() =>
      'MlLabel(label: $label, confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
}
