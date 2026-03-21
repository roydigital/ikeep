import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/ml_label.dart';
import 'service_providers.dart';

/// Returns ML label suggestions for an image at the given path.
/// Results are cached per path within the provider's lifetime.
final mlLabelsForImageProvider =
    FutureProvider.autoDispose.family<List<MlLabel>, String>((ref, imagePath) async {
  return ref.watch(mlLabelServiceProvider).getLabelsForImage(imagePath);
});
