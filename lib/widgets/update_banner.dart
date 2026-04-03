import 'package:flutter/material.dart';

import '../domain/models/effective_app_update_decision.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.decision,
    required this.onUpdateNow,
    required this.onLater,
    this.isActionInProgress = false,
  });

  final EffectiveAppUpdateDecision decision;
  final Future<void> Function() onUpdateNow;
  final Future<void> Function() onLater;
  final bool isActionInProgress;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? AppColors.accentSurfaceDarkStrong
        : AppColors.surfaceVariantLight;
    final borderColor = isDark ? AppColors.borderDark : AppColors.borderLight;
    final titleColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final bodyColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final String primaryLabel = switch (decision.status) {
      EffectiveAppUpdateStatus.downloadedPendingInstall => 'Restart to install',
      EffectiveAppUpdateStatus.downloadingUpdate => 'Downloading...',
      _ => 'Update now',
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppDimensions.spacingMd,
          AppDimensions.spacingSm,
          AppDimensions.spacingMd,
          AppDimensions.spacingSm,
        ),
        padding: const EdgeInsets.all(AppDimensions.spacingMd),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_alt, color: AppColors.primary),
                const SizedBox(width: AppDimensions.spacingSm),
                Expanded(
                  child: Text(
                    decision.title.trim().isEmpty
                        ? 'Update available'
                        : decision.title,
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              decision.message.trim().isEmpty
                  ? 'A newer version of Ikeep is available on Google Play.'
                  : decision.message,
              style: TextStyle(
                color: bodyColor,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            if (decision.showChangelog) ...[
              const SizedBox(height: AppDimensions.spacingSm),
              Text(
                decision.changelogText,
                style: TextStyle(
                  color: bodyColor,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: AppDimensions.spacingMd),
            Row(
              children: [
                ElevatedButton(
                  onPressed: (decision.status ==
                              EffectiveAppUpdateStatus.downloadingUpdate ||
                          isActionInProgress)
                      ? null
                      : () => onUpdateNow(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(primaryLabel),
                ),
                if (decision.isOptionalUpdate) ...[
                  const SizedBox(width: AppDimensions.spacingSm),
                  TextButton(
                    onPressed: isActionInProgress ? null : () => onLater(),
                    child: const Text('Later'),
                  ),
                ],
                if (isActionInProgress) ...[
                  const SizedBox(width: AppDimensions.spacingSm),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
