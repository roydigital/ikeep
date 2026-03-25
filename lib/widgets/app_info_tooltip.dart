import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class AppInfoTooltip extends StatelessWidget {
  const AppInfoTooltip({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'More information about $title',
      child: InkResponse(
        onTap: () => _showInfoSheet(context),
        radius: 18,
        child: const Padding(
          padding: EdgeInsets.all(AppDimensions.spacingXs),
          child: Icon(
            Icons.info_outline,
            size: 20,
            color: AppColors.textFaded,
          ),
        ),
      ),
    );
  }

  Future<void> _showInfoSheet(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimensions.bottomSheetRadius),
        ),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.spacingLg,
            AppDimensions.spacingLg,
            AppDimensions.spacingLg,
            AppDimensions.spacingXl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimaryLight,
                      fontWeight: FontWeight.w800,
                    ) ??
                    const TextStyle(
                      color: AppColors.textPrimaryLight,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              Text(
                description,
                style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondaryLight,
                      height: 1.5,
                    ) ??
                    const TextStyle(
                      color: AppColors.textSecondaryLight,
                      fontSize: 14,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: AppDimensions.spacingLg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDimensions.spacingMd,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.radiusLg,
                      ),
                    ),
                  ),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
