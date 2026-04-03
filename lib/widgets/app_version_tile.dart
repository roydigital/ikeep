import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class AppVersionTile extends StatelessWidget {
  const AppVersionTile({
    super.key,
    required this.versionLabel,
    required this.statusLabel,
    required this.isChecking,
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.isActionInProgress,
    required this.onCheckForUpdates,
    required this.onUpdateNow,
  });

  final String versionLabel;
  final String statusLabel;
  final bool isChecking;
  final bool hasUpdate;
  final bool isForceUpdate;
  final bool isActionInProgress;
  final Future<void> Function() onCheckForUpdates;
  final Future<void> Function() onUpdateNow;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderDark : AppColors.borderLight;
    final titleColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final subtitleColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final statusChipColor = isForceUpdate
        ? AppColors.error
        : (hasUpdate ? AppColors.info : AppColors.success);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: subtitleColor),
              const SizedBox(width: AppDimensions.spacingSm),
              Expanded(
                child: Text(
                  versionLabel,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingSm,
                  vertical: AppDimensions.spacingXs,
                ),
                decoration: BoxDecoration(
                  color: statusChipColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusChipColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: isChecking ? null : () => onCheckForUpdates(),
                icon: isChecking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Check for updates'),
              ),
              if (hasUpdate) ...[
                const SizedBox(width: AppDimensions.spacingSm),
                ElevatedButton(
                  onPressed: isActionInProgress ? null : () => onUpdateNow(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: isActionInProgress
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Update now'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
