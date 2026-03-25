import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../domain/models/item.dart';
import '../../domain/models/location_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/item_providers.dart';
import '../../providers/location_usage_providers.dart';
import '../../providers/main_tab_provider.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';
import '../../widgets/adaptive_image.dart';
import '../../widgets/app_nav_bar.dart';

class HomeTourShowcaseKeys {
  HomeTourShowcaseKeys()
      : fab = GlobalKey(debugLabel: 'homeTourFab'),
        searchBar = GlobalKey(debugLabel: 'homeTourSearchBar'),
        dashboard = GlobalKey(debugLabel: 'homeTourDashboard');

  final GlobalKey fab;
  final GlobalKey searchBar;
  final GlobalKey dashboard;
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.tourKeys,
  });

  final HomeTourShowcaseKeys tourKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _MainContent(
        profilePhotoUrl: user?.photoURL,
        searchShowcaseKey: tourKeys.searchBar,
        dashboardShowcaseKey: tourKeys.dashboard,
      ),
    );
  }
}

// ── Main scrollable content ────────────────────────────────────────────────────

class _MainContent extends ConsumerWidget {
  const _MainContent({
    required this.profilePhotoUrl,
    required this.searchShowcaseKey,
    required this.dashboardShowcaseKey,
  });

  final String? profilePhotoUrl;
  final GlobalKey searchShowcaseKey;
  final GlobalKey dashboardShowcaseKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(allItemsProvider);
    final forgottenItemsAsync = ref.watch(forgottenItemsProvider);

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: AppNavBar.contentBottomSpacing(context, includeFab: true),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, ref),
            const SizedBox(height: AppDimensions.spacingMd),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingMd,
              ),
              child: _buildTourStep(
                showcaseKey: searchShowcaseKey,
                title: 'Find Anything',
                description:
                    'Find anything instantly. Search by name, tags, or location.',
                child: _buildSearchBar(context, ref),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingMd,
              ),
              child: _buildTourStep(
                showcaseKey: dashboardShowcaseKey,
                title: 'Action Needed',
                description:
                    'Keep track of items you\'ve lent out or things expiring soon right here.',
                child: const _ActionNeededCard(),
              ),
            ),
            const SizedBox(height: 18),
            _buildRecentlySaved(context, ref, itemsAsync),
            const SizedBox(height: AppDimensions.spacingLg),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingMd,
              ),
              child: _TopLocationsGrid(),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            _buildForgottenCarousel(context, forgottenItemsAsync),
            const SizedBox(height: AppDimensions.spacingLg),
          ],
        ),
      ),
    );
  }

  Widget _buildForgottenCarousel(
    BuildContext context,
    AsyncValue<List<Item>> forgottenItemsAsync,
  ) {
    final now = DateTime.now();
    if (now.weekday != DateTime.sunday) {
      return const SizedBox.shrink();
    }

    return forgottenItemsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) {
        debugPrint('HomeScreen: forgotten items error: $error');
        return const SizedBox.shrink();
      },
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Did you Forget You Own This?',
                style: TextStyle(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sunday throwback — rediscover things you parked and forgot.',
                style: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              _ForgottenItemsCarousel(items: items),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarBorderColor = isDark
        ? AppColors.primary.withValues(alpha: 0.55)
        : AppColors.borderLight;
    final avatarShadowColor = isDark
        ? AppColors.primary.withValues(alpha: 0.28)
        : AppColors.primary.withValues(alpha: 0.16);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spacingMd,
        AppDimensions.spacingLg,
        AppDimensions.spacingMd,
        0,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            child: Image.asset(
              'assets/optimized/icon.png',
              width: 42,
              height: 42,
              fit: BoxFit.cover,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => ref.read(mainTabProvider.notifier).state = 3,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: avatarBorderColor,
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: avatarShadowColor,
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child:
                        profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty
                            ? Image.network(
                                profilePhotoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _buildProfileFallback(),
                              )
                            : _buildProfileFallback(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileFallback() {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.14),
      child: const Icon(
        Icons.person_outline,
        color: AppColors.primary,
        size: 22,
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => ref.read(mainTabProvider.notifier).state = 2,
      child: Container(
        height: AppDimensions.inputHeight,
        decoration: BoxDecoration(
          color: (isDark
                  ? AppColors.surfaceVariantDark
                  : AppColors.surfaceVariantLight)
              .withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppDimensions.spacingMd),
            Icon(
              Icons.search,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            const SizedBox(width: AppDimensions.spacingSm),
            Expanded(
              child: Text(
                'Search your saved world...',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ),
            const Icon(Icons.mic, color: AppColors.primary),
            const SizedBox(width: AppDimensions.spacingMd),
          ],
        ),
      ),
    );
  }

  Widget _buildTourStep({
    required GlobalKey showcaseKey,
    required String title,
    required String description,
    required Widget child,
  }) {
    return Showcase(
      key: showcaseKey,
      title: title,
      description: description,
      tooltipBackgroundColor: AppColors.surfaceDark,
      textColor: AppColors.textPrimaryDark,
      titleTextStyle: const TextStyle(
        color: AppColors.textPrimaryDark,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
      descTextStyle: const TextStyle(
        color: AppColors.textSecondaryDark,
        fontSize: 14,
        height: 1.45,
      ),
      tooltipBorderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      targetBorderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      targetPadding: const EdgeInsets.all(6),
      overlayOpacity: 0.78,
      disableDefaultTargetGestures: true,
      child: child,
    );
  }

  Widget _buildRecentlySaved(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Item>> itemsAsync,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingMd,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recently Saved',
                style: TextStyle(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextButton(
                onPressed: () => ref.read(mainTabProvider.notifier).state = 2,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'View All',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.spacingSm),
        itemsAsync.when(
          data: (items) {
            if (items.isEmpty) return _buildEmptyState(context, isDark);
            final recent = [...items]
              ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
            final display = recent.take(10).toList();
            return SizedBox(
              height: 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingMd,
                ),
                clipBehavior: Clip.none,
                itemCount: display.length,
                itemBuilder: (context, i) => _ItemCard(item: display[i]),
              ),
            );
          },
          loading: () => SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingMd,
              ),
              itemCount: 4,
              itemBuilder: (_, __) => const _SkeletonCard(),
            ),
          ),
          error: (_, __) => SizedBox(
            height: 180,
            child: Center(
              child: Text(
                'Could not load saved items',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return SizedBox(
      height: 180,
      child: Center(
        child: GestureDetector(
          onTap: () => context.push(AppRoutes.save),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 44,
                color: isDark
                    ? AppColors.textDisabledDark
                    : AppColors.textDisabledLight,
              ),
              const SizedBox(height: AppDimensions.spacingSm),
              Text(
                'Nothing saved yet.\nTap the camera to start!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Household card ─────────────────────────────────────────────────────────────

// ignore: unused_element
class _HouseholdCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.groups_2, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Local-First Inventory',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Social sharing is parked for a future release.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Track where things live, tag them, and manage lending locally inside your own inventory.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => ref.read(mainTabProvider.notifier).state = 2,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Browse Inventory',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionNeededCard extends ConsumerWidget {
  const _ActionNeededCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(allItemsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return itemsAsync.when(
      loading: () => _buildCard(
        context: context,
        isDark: isDark,
        icon: Icons.space_dashboard_rounded,
        title: 'Your Dashboard',
        headline: 'Preparing your lending, expiry, and warranty overview...',
        supportingText:
            'Returns, due dates, and warranty deadlines will show up here.',
        lentOutCount: 0,
        expiringSoonCount: 0,
        warrantyEndingSoonCount: 0,
        isUrgent: false,
      ),
      error: (_, __) => _buildCard(
        context: context,
        isDark: isDark,
        icon: Icons.space_dashboard_rounded,
        title: 'Your Dashboard',
        headline: 'Keep an eye on what needs attention.',
        supportingText:
            'This area surfaces lent items, expiries, and warranty deadlines.',
        lentOutCount: 0,
        expiringSoonCount: 0,
        warrantyEndingSoonCount: 0,
        isUrgent: false,
      ),
      data: (items) {
        final now = DateTime.now();
        final today = dashboardDateOnly(now);
        final activeItems = items.where((item) => !item.isArchived).toList();
        final lentOutCount = activeItems.where((item) => item.isLent).length;
        final overdueReturnCount = activeItems
            .where(
              (item) =>
                  item.isLent &&
                  item.expectedReturnDate != null &&
                  dashboardDateOnly(item.expectedReturnDate!).isBefore(today),
            )
            .length;
        final expiringSoonCount = activeItems.where((item) {
          return isItemExpiringSoon(item, referenceDate: now);
        }).length;
        final warrantyEndingSoonCount = activeItems.where((item) {
          return isItemWarrantyEndingSoon(item, referenceDate: now);
        }).length;

        final hasUrgentItems = overdueReturnCount > 0 ||
            expiringSoonCount > 0 ||
            warrantyEndingSoonCount > 0;
        final headline = _buildHeadline(
          lentOutCount: lentOutCount,
          overdueReturnCount: overdueReturnCount,
          expiringSoonCount: expiringSoonCount,
          warrantyEndingSoonCount: warrantyEndingSoonCount,
        );
        final supportingText = hasUrgentItems
            ? 'Keep borrowing deadlines, expiry reminders, and warranty coverage visible at a glance.'
            : 'As you save, lend, and attach invoices, this dashboard will surface what needs attention.';

        return _buildCard(
          context: context,
          isDark: isDark,
          icon: hasUrgentItems
              ? Icons.warning_amber_rounded
              : Icons.space_dashboard_rounded,
          title: 'Your Dashboard',
          headline: headline,
          supportingText: supportingText,
          lentOutCount: lentOutCount,
          expiringSoonCount: expiringSoonCount,
          warrantyEndingSoonCount: warrantyEndingSoonCount,
          isUrgent: hasUrgentItems,
        );
      },
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required bool isDark,
    required IconData icon,
    required String title,
    required String headline,
    required String supportingText,
    required int lentOutCount,
    required int expiringSoonCount,
    required int warrantyEndingSoonCount,
    required bool isUrgent,
  }) {
    final backgroundColor = isUrgent
        ? (isDark
            ? AppColors.warning.withValues(alpha: 0.16)
            : AppColors.warning.withValues(alpha: 0.12))
        : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight);
    final borderColor = isUrgent
        ? AppColors.warning.withValues(alpha: isDark ? 0.4 : 0.28)
        : (isDark ? AppColors.borderDark : AppColors.borderLight);
    final iconColor =
        isUrgent ? AppColors.warning : AppColors.primary.withValues(alpha: 0.9);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headline,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DashboardMetric(
                  label: 'Lent Out',
                  value: '$lentOutCount',
                  icon: Icons.outbox_rounded,
                  accentColor: AppColors.primary,
                  isDark: isDark,
                  onTap: () => context.push(AppRoutes.dashboardLentOut),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DashboardMetric(
                  label: 'Expiring',
                  value: '$expiringSoonCount',
                  icon: Icons.schedule_rounded,
                  accentColor: AppColors.warning,
                  isDark: isDark,
                  onTap: () => context.push(AppRoutes.dashboardExpiringSoon),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DashboardMetric(
                  label: 'Warranty',
                  value: '$warrantyEndingSoonCount',
                  icon: Icons.verified_user_outlined,
                  accentColor: AppColors.info,
                  isDark: isDark,
                  onTap: () => context.push(AppRoutes.dashboardWarrantyEnding),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            supportingText,
            style: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static String _pluralize(int count, String singular) {
    return count == 1 ? singular : '${singular}s';
  }

  String _buildHeadline({
    required int lentOutCount,
    required int overdueReturnCount,
    required int expiringSoonCount,
    required int warrantyEndingSoonCount,
  }) {
    final highlights = <String>[];
    if (overdueReturnCount > 0) {
      highlights.add(
        '$overdueReturnCount ${_pluralize(overdueReturnCount, "return")} overdue',
      );
    }
    if (expiringSoonCount > 0) {
      highlights.add(
        '$expiringSoonCount ${_pluralize(expiringSoonCount, "item")} expiring soon',
      );
    }
    if (warrantyEndingSoonCount > 0) {
      highlights.add(
        '$warrantyEndingSoonCount ${_pluralize(warrantyEndingSoonCount, "warranty")} ending soon',
      );
    }
    if (highlights.isNotEmpty) {
      return highlights.join(' • ');
    }
    if (lentOutCount > 0) {
      return 'Nothing urgent right now. $lentOutCount ${_pluralize(lentOutCount, "item")} currently shared with others.';
    }
    return 'Nothing urgent right now.';
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingSm,
            vertical: AppDimensions.spacingSm,
          ),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: isDark ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            border: Border.all(
              color: accentColor.withValues(alpha: isDark ? 0.24 : 0.16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: accentColor, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                style: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopLocationsGrid extends ConsumerWidget {
  const _TopLocationsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(locationsWithDerivedUsageProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Locations',
          style: TextStyle(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Jump back into the places you use most.',
          style: TextStyle(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        locationsAsync.when(
          loading: () => _TopLocationsGridSkeleton(isDark: isDark),
          error: (_, __) => const SizedBox.shrink(),
          data: (locations) {
            final ranked = [...locations]
              ..sort((a, b) => b.usageCount.compareTo(a.usageCount));
            final display = ranked
                .where((location) => location.usageCount > 0)
                .take(6)
                .toList();

            if (display.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDimensions.spacingMd),
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                  border: Border.all(
                    color:
                        isDark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
                child: Text(
                  'Save a few items with locations to unlock quick access here.',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    fontSize: 13,
                  ),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 520 ? 3 : 2;
                final spacing = AppDimensions.spacingSm;
                final itemWidth =
                    (constraints.maxWidth - ((columns - 1) * spacing)) /
                        columns;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final location in display)
                      SizedBox(
                        width: itemWidth,
                        child: _TopLocationTile(location: location),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _TopLocationTile extends StatelessWidget {
  const _TopLocationTile({required this.location});

  final LocationModel location;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = _iconForLocation(location.iconName);

    return InkWell(
      onTap: () => context.push(
        AppRoutes.search,
        extra: {'initialQuery': location.fullPath ?? location.name},
      ),
      borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      child: Ink(
        padding: const EdgeInsets.all(AppDimensions.spacingMd),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text(
              location.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              location.fullPath ?? 'Quick access location',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              location.usageCount == 1
                  ? '1 item'
                  : '${location.usageCount} items',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopLocationsGridSkeleton extends StatelessWidget {
  const _TopLocationsGridSkeleton({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 520 ? 3 : 2;
        final spacing = AppDimensions.spacingSm;
        final itemWidth =
            (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: List.generate(
            columns * 2,
            (_) => Container(
              width: itemWidth,
              height: 132,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

IconData _iconForLocation(String iconName) {
  switch (iconName) {
    case 'bed':
      return Icons.bed_rounded;
    case 'living':
      return Icons.chair_rounded;
    case 'kitchen':
      return Icons.kitchen_rounded;
    case 'garage':
      return Icons.garage_rounded;
    case 'bath':
      return Icons.bathtub_outlined;
    case 'office':
      return Icons.work_outline_rounded;
    case 'dining':
      return Icons.restaurant_rounded;
    case 'door':
      return Icons.door_sliding_outlined;
    case 'shelves':
      return Icons.table_rows_rounded;
    default:
      return Icons.inventory_2_outlined;
  }
}

// ── Lent items pulse section ───────────────────────────────────────────────────

// ignore: unused_element
class _LentPulseSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lentAsync = ref.watch(lentItemsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return lentAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (lentItems) {
        if (lentItems.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.outbox, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'I Lent It \u2022 ${lentItems.length} active',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...lentItems.take(3).map((item) {
                  final due = item.expectedReturnDate ?? item.lentOn;
                  final dueText = due == null
                      ? 'No return date'
                      : 'Return ${due.day}/${due.month}/${due.year}';
                  return GestureDetector(
                    onTap: () =>
                        context.push(AppRoutes.itemDetailPath(item.uuid)),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: item.imagePaths.isNotEmpty
                                ? AdaptiveImage(
                                    path: item.imagePaths.first,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_) => const Icon(
                                      Icons.image_outlined,
                                      color: AppColors.primary,
                                      size: 18,
                                    ),
                                  )
                                : const Icon(Icons.image_outlined,
                                    color: AppColors.primary, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.textPrimaryDark
                                        : AppColors.textPrimaryLight,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'with ${item.lentTo ?? 'someone'} \u2022 $dueText',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  );
                }),
                if (lentItems.length > 3) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      '+${lentItems.length - 3} more lent out',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Item card ──────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => context.push(AppRoutes.itemDetailPath(item.uuid)),
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: AppDimensions.spacingMd),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: item.imagePaths.isNotEmpty
                  ? AdaptiveImage(
                      path: item.imagePaths.first,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_) => const _Placeholder(),
                    )
                  : const _Placeholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(AppDimensions.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (item.isLent)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.outbox,
                              color: AppColors.primary, size: 12),
                        ),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.isLent
                        ? 'Lent to ${item.lentTo ?? 'someone'}'
                        : _timeAgo(item.savedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color:
          isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 36,
          color:
              isDark ? AppColors.textDisabledDark : AppColors.textDisabledLight,
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: AppDimensions.spacingMd),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
    );
  }
}

class _ForgottenItemsCarousel extends StatefulWidget {
  const _ForgottenItemsCarousel({required this.items});

  final List<Item> items;

  @override
  State<_ForgottenItemsCarousel> createState() =>
      _ForgottenItemsCarouselState();
}

class _ForgottenItemsCarouselState extends State<_ForgottenItemsCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 210,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ForgottenItemCard(item: item),
              );
            },
          ),
        ),
        if (widget.items.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.items.length, (index) {
              final active = _currentPage == index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _ForgottenItemCard extends StatelessWidget {
  const _ForgottenItemCard({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => context.push(AppRoutes.itemDetailPath(item.uuid)),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 124,
              child: item.imagePaths.isNotEmpty
                  ? AdaptiveImage(
                      path: item.imagePaths.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_) => const _Placeholder(),
                    )
                  : const _Placeholder(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppDimensions.spacingSm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'You saved this ${_savedMonthsAgo(item.savedAt)} and haven\'t searched for it.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap to revisit',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _savedMonthsAgo(DateTime savedAt) {
    final diffDays = DateTime.now().difference(savedAt).inDays;
    final months = (diffDays / 30).floor();
    if (months <= 1) return '1 month ago';
    return '$months months ago';
  }
}
