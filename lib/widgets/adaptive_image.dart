import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/storage_constants.dart';
import '../core/utils/path_utils.dart';
import '../providers/service_providers.dart';
import '../theme/app_colors.dart';

/// Displays an image from either a local file path or a remote HTTPS/gs:// URL.
///
/// Falls back gracefully when the image is missing or fails to load:
/// - A custom [errorBuilder] is shown if provided.
/// - Otherwise a visible broken-image placeholder is displayed so the user
///   can tell at a glance that an attachment is unresolved rather than seeing
///   a blank space.
enum AdaptiveImageVariant { thumbnail, fullImage }

class AdaptiveImage extends ConsumerStatefulWidget {
  const AdaptiveImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.itemUuid,
    this.imageIndex = 0,
    this.variant = AdaptiveImageVariant.fullImage,
    this.errorBuilder,
  });

  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? itemUuid;
  final int imageIndex;
  final AdaptiveImageVariant variant;

  /// Widget shown when the image cannot be loaded. If null, a default
  /// broken-image placeholder is shown (never invisible SizedBox.shrink).
  final WidgetBuilder? errorBuilder;

  @override
  ConsumerState<AdaptiveImage> createState() => _AdaptiveImageState();
}

class _AdaptiveImageState extends ConsumerState<AdaptiveImage> {
  late Future<String?> _resolvedPathFuture;

  @override
  void initState() {
    super.initState();
    _resolvedPathFuture = _resolvePath();
  }

  @override
  void didUpdateWidget(covariant AdaptiveImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.itemUuid != widget.itemUuid ||
        oldWidget.imageIndex != widget.imageIndex ||
        oldWidget.variant != widget.variant) {
      _resolvedPathFuture = _resolvePath();
    }
  }

  Future<String?> _resolvePath() async {
    final trimmedPath = widget.path.trim();
    if (!_shouldUseCloudLookup(trimmedPath)) {
      return trimmedPath;
    }

    return ref.read(itemCloudMediaServiceProvider).resolveImagePath(
          itemUuid: widget.itemUuid!.trim(),
          imageIndex: widget.imageIndex,
          preferThumbnail: widget.variant == AdaptiveImageVariant.thumbnail,
          fallbackPath: trimmedPath,
        );
  }

  @override
  Widget build(BuildContext context) {
    final errorWidget =
        widget.errorBuilder?.call(context) ?? _BrokenImagePlaceholder(
      width: widget.width,
      height: widget.height,
    );

    final trimmedPath = widget.path.trim();
    if (!_shouldUseCloudLookup(trimmedPath)) {
      return _buildResolvedImage(trimmedPath, errorWidget);
    }

    return FutureBuilder<String?>(
      future: _resolvedPathFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          );
        }

        final resolvedPath = (snapshot.data ?? '').trim();
        if (resolvedPath.isEmpty) {
          return errorWidget;
        }

        return _buildResolvedImage(resolvedPath, errorWidget);
      },
    );
  }

  bool _shouldUseCloudLookup(String path) {
    final itemUuid = widget.itemUuid?.trim();
    if (path.isEmpty || itemUuid == null || itemUuid.isEmpty) {
      return false;
    }

    final looksLikeStoragePath =
        path.startsWith('${StorageConstants.firebaseItemImagesRoot}/');
    return PathUtils.isRemotePath(path) || looksLikeStoragePath;
  }

  Widget _buildResolvedImage(String resolvedPath, Widget errorWidget) {
    if (PathUtils.isRemotePath(resolvedPath)) {
      return Image.network(
        resolvedPath,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        loadingBuilder: (_, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return SizedBox(
            width: widget.width,
            height: widget.height,
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
      File(resolvedPath),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
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
