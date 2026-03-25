import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';
import '../../widgets/adaptive_image.dart';

enum DashboardItemsMode { lentOut, expiringSoon, warrantyEndingSoon }

class DashboardItemsScreen extends ConsumerWidget {
  const DashboardItemsScreen({
    super.key,
    required this.mode,
  });

  final DashboardItemsMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemsAsync = switch (mode) {
      DashboardItemsMode.lentOut => ref.watch(lentItemsProvider),
      DashboardItemsMode.expiringSoon => ref.watch(expiringSoonItemsProvider),
      DashboardItemsMode.warrantyEndingSoon =>
        ref.watch(warrantyEndingSoonItemsProvider),
    };

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          mode.title,
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _DashboardItemsFeedback(
            mode: mode,
            isDark: isDark,
            title: 'Unable to load this list',
            message: 'Try reopening it or refresh the items and try again.',
            actionLabel: 'Retry',
            onAction: () {
              if (mode == DashboardItemsMode.lentOut) {
                ref.invalidate(lentItemsProvider);
              } else if (mode == DashboardItemsMode.expiringSoon) {
                ref.invalidate(expiringSoonItemsProvider);
              } else {
                ref.invalidate(warrantyEndingSoonItemsProvider);
              }
            },
          ),
          data: (items) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.spacingMd,
                  AppDimensions.spacingXs,
                  AppDimensions.spacingMd,
                  AppDimensions.spacingMd,
                ),
                child: _DashboardSummaryCard(
                  mode: mode,
                  count: items.length,
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? _DashboardItemsFeedback(
                        mode: mode,
                        isDark: isDark,
                        title: mode.emptyTitle,
                        message: mode.emptyMessage,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimensions.spacingMd,
                          0,
                          AppDimensions.spacingMd,
                          AppDimensions.spacingLg,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppDimensions.spacingSm),
                        itemBuilder: (context, index) => _DashboardItemCard(
                          item: items[index],
                          mode: mode,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on DashboardItemsMode {
  String get title => switch (this) {
        DashboardItemsMode.lentOut => 'Lent Out',
        DashboardItemsMode.expiringSoon => 'Expiring Soon',
        DashboardItemsMode.warrantyEndingSoon => 'Warranty Ending Soon',
      };

  IconData get icon => switch (this) {
        DashboardItemsMode.lentOut => Icons.outbox_rounded,
        DashboardItemsMode.expiringSoon => Icons.schedule_rounded,
        DashboardItemsMode.warrantyEndingSoon => Icons.verified_user_outlined,
      };

  Color get accentColor => switch (this) {
        DashboardItemsMode.lentOut => AppColors.primary,
        DashboardItemsMode.expiringSoon => AppColors.warning,
        DashboardItemsMode.warrantyEndingSoon => AppColors.info,
      };

  String headline(int count) => switch (this) {
        DashboardItemsMode.lentOut => count == 0
            ? 'Nothing is lent out right now.'
            : '$count ${_pluralize(count, "item")} currently shared with others.',
        DashboardItemsMode.expiringSoon => count == 0
            ? 'No items expiring within $dashboardExpiringSoonWindowDays days.'
            : '$count ${_pluralize(count, "item")} expiring within '
                '$dashboardExpiringSoonWindowDays days.',
        DashboardItemsMode.warrantyEndingSoon => count == 0
            ? 'No warranties ending within $dashboardWarrantyEndingSoonWindowDays days.'
            : '$count ${_pluralize(count, "item")} with warranty ending within '
                '$dashboardWarrantyEndingSoonWindowDays days.',
      };

  String get supportingText => switch (this) {
        DashboardItemsMode.lentOut =>
          'Sharing is a thoughtful habit. Items with a return date are listed first so the nearest check-in stays on top.',
        DashboardItemsMode.expiringSoon =>
          'Sorted by nearest expiry date so the next item to expire stays at the top.',
        DashboardItemsMode.warrantyEndingSoon =>
          'Keep the invoice and warranty deadline visible so you can act before coverage runs out.',
      };

  String get emptyTitle => switch (this) {
        DashboardItemsMode.lentOut => 'Nothing shared yet',
        DashboardItemsMode.expiringSoon => 'Nothing expiring soon',
        DashboardItemsMode.warrantyEndingSoon => 'No warranty deadlines yet',
      };

  String get emptyMessage => switch (this) {
        DashboardItemsMode.lentOut =>
          'When you share something with a neighbour, friend, or family member, it will appear here with its return timeline.',
        DashboardItemsMode.expiringSoon =>
          'Items with an expiry date inside the next '
              '$dashboardExpiringSoonWindowDays days will show up here.',
        DashboardItemsMode.warrantyEndingSoon =>
          'Items with a warranty end date inside the next '
              '$dashboardWarrantyEndingSoonWindowDays days will show up here.',
      };
}

class _DashboardSummaryCard extends StatelessWidget {
  const _DashboardSummaryCard({
    required this.mode,
    required this.count,
    required this.isDark,
  });

  final DashboardItemsMode mode;
  final int count;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final borderColor = mode.accentColor.withValues(
      alpha: isDark ? 0.38 : 0.24,
    );
    final backgroundColor = mode.accentColor.withValues(
      alpha: isDark ? 0.14 : 0.1,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: mode.accentColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
            child: Icon(mode.icon, color: mode.accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode.headline(count),
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  mode.supportingText,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardItemCard extends StatelessWidget {
  const _DashboardItemCard({
    required this.item,
    required this.mode,
  });

  final Item item;
  final DashboardItemsMode mode;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderDark : AppColors.borderLight;
    final titleColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final subtitleColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final locationText = _locationLabel(item);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        onTap: () => context.push(AppRoutes.itemDetailPath(item.uuid)),
        child: Ink(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.spacingMd),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DashboardItemThumbnail(item: item),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _primaryLine(item, mode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mode == DashboardItemsMode.expiringSoon
                            ? (locationText ??
                                'Open details to review this item.')
                            : mode == DashboardItemsMode.warrantyEndingSoon
                                ? _warrantySecondaryLine(item, locationText)
                                : _lentTimelineLine(item),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _DashboardStatusPill(
                      label: _statusLabel(item, mode),
                      color: _statusColor(item, mode),
                    ),
                    const SizedBox(height: 18),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: subtitleColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _primaryLine(Item item, DashboardItemsMode mode) {
    if (mode == DashboardItemsMode.expiringSoon) {
      return 'Expires ${DateFormat('dd MMM yyyy').format(item.expiryDate!)}';
    }
    if (mode == DashboardItemsMode.warrantyEndingSoon) {
      return 'Warranty ends ${DateFormat('dd MMM yyyy').format(item.warrantyEndDate!)}';
    }

    final lentTo = item.lentTo?.trim();
    if (lentTo != null && lentTo.isNotEmpty) {
      return 'Lent to $lentTo';
    }
    return 'Currently shared with someone';
  }

  static String _lentTimelineLine(Item item) {
    final expectedReturnDate = item.expectedReturnDate;
    if (expectedReturnDate != null) {
      return 'Return by ${DateFormat('dd MMM yyyy').format(expectedReturnDate)}';
    }

    final lentOn = item.lentOn;
    if (lentOn != null) {
      return 'Lent on ${DateFormat('dd MMM yyyy').format(lentOn)}';
    }

    return 'No return date recorded yet.';
  }

  static String _warrantySecondaryLine(Item item, String? locationText) {
    final invoiceName = item.invoiceFileName?.trim();
    if (invoiceName != null && invoiceName.isNotEmpty) {
      if (locationText != null && locationText.isNotEmpty) {
        return '$invoiceName • $locationText';
      }
      return invoiceName;
    }

    return locationText ?? 'Open details to review invoice coverage.';
  }

  static String _statusLabel(Item item, DashboardItemsMode mode) {
    final today = dashboardDateOnly(DateTime.now());
    if (mode == DashboardItemsMode.expiringSoon) {
      final daysUntilExpiry =
          dashboardDateOnly(item.expiryDate!).difference(today).inDays;
      if (daysUntilExpiry == 0) return 'Today';
      if (daysUntilExpiry == 1) return 'Tomorrow';
      return 'In $daysUntilExpiry d';
    }
    if (mode == DashboardItemsMode.warrantyEndingSoon) {
      final daysUntilWarrantyEnd =
          dashboardDateOnly(item.warrantyEndDate!).difference(today).inDays;
      if (daysUntilWarrantyEnd == 0) return 'Today';
      if (daysUntilWarrantyEnd == 1) return 'Tomorrow';
      return 'In $daysUntilWarrantyEnd d';
    }

    final expectedReturnDate = item.expectedReturnDate;
    if (expectedReturnDate == null) return 'No date';

    final daysUntilReturn =
        dashboardDateOnly(expectedReturnDate).difference(today).inDays;
    if (daysUntilReturn < 0) return 'Overdue';
    if (daysUntilReturn == 0) return 'Due today';
    if (daysUntilReturn == 1) return 'Due tomorrow';
    return 'Due in $daysUntilReturn d';
  }

  static Color _statusColor(Item item, DashboardItemsMode mode) {
    if (mode == DashboardItemsMode.expiringSoon) {
      return AppColors.warning;
    }
    if (mode == DashboardItemsMode.warrantyEndingSoon) {
      final today = dashboardDateOnly(DateTime.now());
      final daysUntilWarrantyEnd =
          dashboardDateOnly(item.warrantyEndDate!).difference(today).inDays;
      return daysUntilWarrantyEnd <= 7 ? AppColors.warning : AppColors.info;
    }

    final expectedReturnDate = item.expectedReturnDate;
    if (expectedReturnDate == null) {
      return AppColors.info;
    }

    final today = dashboardDateOnly(DateTime.now());
    final isOverdue = dashboardDateOnly(expectedReturnDate).isBefore(today);
    return isOverdue ? AppColors.error : AppColors.primary;
  }

  static String? _locationLabel(Item item) {
    final locationFullPath = item.locationFullPath?.trim();
    if (locationFullPath != null && locationFullPath.isNotEmpty) {
      return locationFullPath;
    }

    final locationName = item.locationName?.trim();
    if (locationName != null && locationName.isNotEmpty) {
      return locationName;
    }

    final hierarchy = [
      item.areaName?.trim(),
      item.roomName?.trim(),
      item.zoneName?.trim(),
    ]
        .where((value) => value != null && value.isNotEmpty)
        .cast<String>()
        .toList();

    if (hierarchy.isEmpty) return null;
    return hierarchy.join(' / ');
  }
}

class _DashboardItemThumbnail extends StatelessWidget {
  const _DashboardItemThumbnail({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: item.imagePaths.isNotEmpty
          ? AdaptiveImage(
              path: item.imagePaths.first,
              fit: BoxFit.cover,
              errorBuilder: (_) => const Icon(
                Icons.image_outlined,
                color: AppColors.primary,
                size: 22,
              ),
            )
          : const Icon(
              Icons.inventory_2_outlined,
              color: AppColors.primary,
              size: 22,
            ),
    );
  }
}

class _DashboardStatusPill extends StatelessWidget {
  const _DashboardStatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DashboardItemsFeedback extends StatelessWidget {
  const _DashboardItemsFeedback({
    required this.mode,
    required this.isDark,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final DashboardItemsMode mode;
  final bool isDark;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDimensions.spacingLg),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: mode.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                ),
                child: Icon(mode.icon, color: mode.accentColor, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _pluralize(int count, String singular) {
  return count == 1 ? singular : '${singular}s';
}
