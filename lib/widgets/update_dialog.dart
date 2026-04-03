import 'package:flutter/material.dart';

import '../domain/models/effective_app_update_decision.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.decision,
    required this.onUpdateNow,
    required this.onLater,
  });

  final EffectiveAppUpdateDecision decision;
  final Future<void> Function() onUpdateNow;
  final Future<void> Function() onLater;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final titleColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final bodyColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      ),
      title: Text(
        decision.title.trim().isEmpty
            ? 'A new version of Ikeep is available'
            : decision.title,
        style: TextStyle(
          color: titleColor,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              decision.message.trim().isEmpty
                  ? 'Update now for the latest fixes and improvements.'
                  : decision.message,
              style: TextStyle(
                color: bodyColor,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (decision.showChangelog) ...[
              const SizedBox(height: AppDimensions.spacingMd),
              Text(
                'What\'s new',
                style: TextStyle(
                  color: titleColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXs),
              Text(
                decision.changelogText,
                style: TextStyle(
                  color: bodyColor,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await onLater();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('Later'),
        ),
        ElevatedButton(
          onPressed: () async {
            await onUpdateNow();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Update now'),
        ),
      ],
    );
  }
}
