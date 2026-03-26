import 'dart:io';

import 'package:flutter/material.dart';

import '../core/utils/path_utils.dart';
import '../theme/app_colors.dart';

/// Displays an image from either a local file path or a remote HTTPS/gs:// URL.
///
/// Falls back gracefully when the image is missing or fails to load:
/// - A custom [errorBuilder] is shown if provided.
/// - Otherwise a visible broken-image placeholder is displayed so the user
///   can tell at a glance that an attachment is unresolved rather than seeing
///   a blank space.
class AdaptiveImage extends StatelessWidget {
  const AdaptiveImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
  });

  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Widget shown when the image cannot be loaded. If null, a default
  /// broken-image placeholder is shown (never invisible SizedBox.shrink).
  final WidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final errorWidget = errorBuilder?.call(context) ?? _BrokenImagePlaceholder(
      width: width,
      height: height,
    );

    if (PathUtils.isRemotePath(path)) {
      return Image.network(
        path,
        fit: fit,
        width: width,
        height: height,
        // Show a loading spinner while the network image is fetching.
        loadingBuilder: (_, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return SizedBox(
            width: width,
            height: height,
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => errorWidget,
      );
    }

    return Image.file(
      File(path),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => errorWidget,
    );
  }
}

/// Default placeholder shown when an image fails to load.
///
/// Shows a camera-off icon on a muted background so the user can see that an
/// attachment slot exists but could not be resolved — rather than seeing a
/// completely blank area with no indication of a problem.
class _BrokenImagePlaceholder extends StatelessWidget {
  const _BrokenImagePlaceholder({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      color: isDark
          ? AppColors.surfaceVariantDark
          : AppColors.surfaceVariantLight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 28,
              color: isDark
                  ? AppColors.textDisabledDark
                  : AppColors.textDisabledLight,
            ),
            const SizedBox(height: 4),
            Text(
              'Image unavailable',
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppColors.textDisabledDark
                    : AppColors.textDisabledLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
