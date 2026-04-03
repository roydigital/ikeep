import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models/effective_app_update_decision.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    super.key,
    required this.decision,
    required this.isActionInProgress,
    required this.onUpdateNow,
    this.onExitApp,
  });

  final EffectiveAppUpdateDecision decision;
  final bool isActionInProgress;
  final Future<void> Function() onUpdateNow;
  final VoidCallback? onExitApp;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final titleColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final bodyColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return ColoredBox(
      color: bgColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.spacingLg),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(AppDimensions.spacingLg),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.system_update_alt_rounded,
                    size: 52,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppDimensions.spacingMd),
                  Text(
                    decision.title.trim().isEmpty
                        ? 'Update required'
                        : decision.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingSm),
                  Text(
                    decision.message.trim().isEmpty
                        ? 'This version is no longer supported. Please update Ikeep to continue.'
                        : decision.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: bodyColor,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (decision.showChangelog) ...[
                    const SizedBox(height: AppDimensions.spacingMd),
                    Text(
                      decision.changelogText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppDimensions.spacingLg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          isActionInProgress ? null : () => onUpdateNow(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppDimensions.spacingMd,
                        ),
                      ),
                      child: isActionInProgress
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Update now'),
                    ),
                  ),
                  if (onExitApp != null && Platform.isAndroid) ...[
                    const SizedBox(height: AppDimensions.spacingSm),
                    TextButton(
                      onPressed: isActionInProgress ? null : onExitApp,
                      child: const Text('Exit app'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
