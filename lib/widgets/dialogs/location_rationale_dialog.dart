import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';

/// Play-Store-compliant prominent disclosure shown before the OS location
/// permission prompt. Must run the first time iKeep needs to resolve the
/// user's area, so the user understands why the permission is requested.
class LocationRationaleDialog extends StatelessWidget {
  const LocationRationaleDialog({super.key});

  /// Shows the rationale as a blocking modal.
  /// Returns `true` if the user tapped "Enable Location", `false` otherwise
  /// (including back-button dismissal — though barrier tap is disabled).
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const LocationRationaleDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final titleColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final bodyColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Dialog(
      backgroundColor: bgColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.spacingLg,
            AppDimensions.spacingLg,
            AppDimensions.spacingLg,
            AppDimensions.spacingMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.primary,
                    size: AppDimensions.iconXl,
                  ),
                ),
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              Text(
                'Why does iKeep need location?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              _BulletRow(
                text:
                    "Auto-detect the area where you're storing items (e.g., 'Home — Noida').",
                color: bodyColor,
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              _BulletRow(
                text:
                    'We never store your exact GPS coordinates — only the area name.',
                color: bodyColor,
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              _BulletRow(
                text:
                    'This is optional — you can always type locations manually.',
                color: bodyColor,
              ),
              const SizedBox(height: AppDimensions.spacingLg),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: bodyColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusMd),
                        ),
                      ),
                      child: const Text(
                        'Not Now',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingSm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusMd),
                        ),
                      ),
                      child: const Text(
                        'Enable Location',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: AppDimensions.spacingSm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
