import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/models/item_location_history.dart';
import '../providers/auth_providers.dart';
import '../providers/history_providers.dart';
import '../theme/app_colors.dart';

class ItemActivityTimeline extends ConsumerWidget {
  const ItemActivityTimeline({
    super.key,
    required this.itemUuid,
    this.showUserAttribution = false,
    this.title = 'Activity Timeline',
  });

  final String itemUuid;
  final bool showUserAttribution;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(itemHistoryProvider(itemUuid));
    final currentUserId = ref.watch(authStateProvider).valueOrNull?.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          historyAsync.when(
            data: (history) {
              if (history.isEmpty) {
                return Text(
                  'No activity recorded yet.',
                  style: TextStyle(color: textSecondary),
                );
              }

              final sorted = [...history]
                ..sort((a, b) => b.movedAt.compareTo(a.movedAt));

              return Column(
                children: [
                  for (var i = 0; i < sorted.length; i++)
                    _TimelineTile(
                      isLast: i == sorted.length - 1,
                      title: sorted[i].resolvedActionDescription,
                      subtitle: _buildSubtitle(
                        sorted[i],
                        currentUserId: currentUserId,
                      ),
                    ),
                ],
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
            error: (error, _) => Text(
              'Could not load history: $error',
              style: TextStyle(color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  String _buildSubtitle(
    ItemLocationHistory history, {
    required String? currentUserId,
  }) {
    final formattedDate = DateFormat(
      'dd MMM yyyy, h:mm a',
    ).format(history.movedAt);

    if (!showUserAttribution) {
      return formattedDate;
    }

    final actorName =
        history.userId != null && history.userId == currentUserId
            ? 'You'
            : history.userName ?? history.userEmail ?? 'Unknown';

    return '$actorName • $formattedDate';
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.isLast,
    required this.title,
    required this.subtitle,
  });

  final bool isLast;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppColors.primary.withValues(alpha: 0.22),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
