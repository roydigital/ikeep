import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/item.dart';
import '../domain/models/item_visibility.dart';
import '../providers/household_providers.dart';
import '../theme/app_colors.dart';

class ItemVisibilityToggle extends ConsumerStatefulWidget {
  const ItemVisibilityToggle({
    super.key,
    required this.item,
  });

  final Item item;

  @override
  ConsumerState<ItemVisibilityToggle> createState() =>
      _ItemVisibilityToggleState();
}

class _ItemVisibilityToggleState extends ConsumerState<ItemVisibilityToggle> {
  bool _isToggling = false;

  Future<void> _toggle() async {
    setState(() => _isToggling = true);

    final error = await ref
        .read(householdNotifierProvider.notifier)
        .toggleItemVisibility(widget.item);

    if (!mounted) return;
    setState(() => _isToggling = false);

    final wasHousehold =
        widget.item.visibility == ItemVisibility.household;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasHousehold
              ? 'Item set to private'
              : 'Item shared with household'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(householdNotifierProvider);
    final hasHousehold = ref.watch(hasHouseholdProvider);
    final isHousehold = widget.item.visibility == ItemVisibility.household;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final isDisabled =
        _isToggling || actionState.isLoading || (!hasHousehold && !isHousehold);

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
                    if (_isToggling)
                      Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isHousehold
                                ? 'Setting to private...'
                                : 'Sharing with household...',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      )
                    else
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
              if (_isToggling)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                Switch.adaptive(
                  value: isHousehold,
                  activeColor: AppColors.primary,
                  onChanged: isDisabled ? null : (_) => _toggle(),
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
}
