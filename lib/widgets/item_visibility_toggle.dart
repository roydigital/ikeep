import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/item.dart';
import '../domain/models/item_visibility.dart';
import '../providers/household_providers.dart';
import '../theme/app_colors.dart';

class ItemVisibilityToggle extends ConsumerWidget {
  const ItemVisibilityToggle({
    super.key,
    required this.item,
  });

  final Item item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(householdNotifierProvider);
    final hasHousehold = ref.watch(hasHouseholdProvider);
    final isHousehold = item.visibility == ItemVisibility.household;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visibility',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isHousehold
                          ? 'This item is shared with your household.'
                          : 'This item is only visible on this device.',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isHousehold,
                activeColor: AppColors.primary,
                onChanged: actionState.isLoading || (!hasHousehold && !isHousehold)
                    ? null
                    : (_) => _toggle(context, ref),
              ),
            ],
          ),
          if (!hasHousehold && !isHousehold) ...[
            const SizedBox(height: 12),
            Text(
              'Create a household in Family Shared Pool settings before enabling shared visibility.',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final error =
        await ref.read(householdNotifierProvider.notifier).toggleItemVisibility(item);
    if (error == null || !context.mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error)));
  }
}
