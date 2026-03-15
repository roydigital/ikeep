import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/item.dart';
import '../../providers/item_providers.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Stack(
        children: [
          Positioned.fill(
            child: _MainContent(bottomInset: bottomInset),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomNav(bottomInset: bottomInset),
          ),
          _Fab(bottomInset: bottomInset),
        ],
      ),
    );
  }
}

// ── Main scrollable content ────────────────────────────────────────────────────

class _MainContent extends ConsumerWidget {
  const _MainContent({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(allItemsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, isDark),
              const SizedBox(height: AppDimensions.spacingMd),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingMd,
                ),
                child: _buildSearchBar(context, isDark),
              ),
            ],
          ),
        ),
        const Spacer(),
        _buildRecentlySaved(context, itemsAsync, isDark),
        SizedBox(height: bottomInset + 72),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spacingMd,
        AppDimensions.spacingLg,
        AppDimensions.spacingMd,
        0,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
            child: const Icon(Icons.push_pin, color: Colors.white, size: 22),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          Text(
            'Ikeep',
            style: TextStyle(
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.push(AppRoutes.settings),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.person_outline,
                color: AppColors.primary,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.search),
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

  Widget _buildRecentlySaved(
    BuildContext context,
    AsyncValue<List<Item>> itemsAsync,
    bool isDark,
  ) {
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
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextButton(
                onPressed: () {},
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
                    fontSize: 18,
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
            if (items.isEmpty) return _buildEmptyState(isDark);
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
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return SizedBox(
      height: 180,
      child: Center(
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
                  ? Image.file(
                      File(item.imagePaths.first),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _Placeholder(),
                    )
                  : _Placeholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(AppDimensions.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
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
                  const SizedBox(height: 2),
                  Text(
                    _timeAgo(item.savedAt),
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

// ── Floating action button ─────────────────────────────────────────────────────

class _Fab extends StatelessWidget {
  const _Fab({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final fabBottom = bottomInset + 58.0 - 14.0;
    return Positioned(
      bottom: fabBottom,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => context.push(AppRoutes.save),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  blurRadius: 28,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: const Icon(
              Icons.photo_camera,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom navigation bar ──────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 10, 8, bottomInset + 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        border: Border(
          top: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          _NavItem(
            label: 'ITEMS',
            icon: Icons.inventory_2,
            active: true,
            onTap: () {},
          ),
          _NavItem(
            label: 'LOCATIONS',
            icon: Icons.location_on,
            active: false,
            onTap: () => context.go(AppRoutes.rooms),
          ),
          const SizedBox(width: 64), // reserve space for FAB
          _NavItem(
            label: 'SEARCH',
            icon: Icons.search,
            active: false,
            onTap: () => context.push(AppRoutes.search),
          ),
          _NavItem(
            label: 'SETTINGS',
            icon: Icons.settings,
            active: false,
            onTap: () => context.go(AppRoutes.settings),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = active
        ? AppColors.primary
        : (isDark
            ? AppColors.textSecondaryDark
            : AppColors.textSecondaryLight);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 27),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
