import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/main_tab_provider.dart';
import '../routing/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

/// Which main tab is currently active.
enum AppNavTab { items, locations, search, settings }

/// Shared bottom navigation bar — glassmorphic vibrant design.
class AppNavBar extends ConsumerWidget {
  const AppNavBar({super.key, required this.activeTab, this.onTabChanged});

  final AppNavTab activeTab;
  final ValueChanged<AppNavTab>? onTabChanged;

  static const double _topPadding = 10;
  static const double _bottomPadding = 10;
  static const double _itemVerticalPadding = 6;
  static const double _iconSize = 26;
  static const double _iconLabelGap = 5;
  static const double _labelFontSize = 10.5;
  static const double _fabSize = 72;
  static const double _fabBottomOffset = 44;
  static const double contentMargin = 20;

  static double navBarHeight(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return bottomInset +
        _topPadding +
        _bottomPadding +
        (_itemVerticalPadding * 2) +
        _iconSize +
        _iconLabelGap +
        _labelFontSize +
        16;
  }

  static double fabClearance(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final fabTop = bottomInset + _fabBottomOffset + _fabSize;
    return fabTop + contentMargin;
  }

  static double contentBottomSpacing(
    BuildContext context, {
    bool includeFab = false,
  }) {
    final navClearance = navBarHeight(context) + contentMargin;
    if (!includeFab) return navClearance;
    final fabClearanceValue = fabClearance(context);
    return fabClearanceValue > navClearance ? fabClearanceValue : navClearance;
  }

  static double fabBottom(BuildContext context) {
    return MediaQuery.paddingOf(context).bottom + _fabBottomOffset;
  }

  void _handleTap(BuildContext context, WidgetRef ref, AppNavTab tab) {
    if (tab == activeTab) return;
    if (onTabChanged != null) {
      onTabChanged!(tab);
    } else {
      ref.read(mainTabProvider.notifier).state = tab.index;
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            AppDimensions.spacingSm,
            _topPadding,
            AppDimensions.spacingSm,
            bottomInset + _bottomPadding,
          ),
          decoration: BoxDecoration(
            color:
                (isDark ? AppColors.backgroundDark : AppColors.backgroundLight)
                    .withValues(alpha: 0.7),
            border: Border(
              top: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              _NavItem(
                label: 'ITEMS',
                icon: Icons.inventory_2_outlined,
                activeIcon: Icons.inventory_2_rounded,
                active: activeTab == AppNavTab.items,
                onTap: () => _handleTap(context, ref, AppNavTab.items),
              ),
              _NavItem(
                label: 'LOCATIONS',
                icon: Icons.location_on_outlined,
                activeIcon: Icons.location_on_rounded,
                active: activeTab == AppNavTab.locations,
                onTap: () => _handleTap(context, ref, AppNavTab.locations),
              ),
              _NavItem(
                label: 'SEARCH',
                icon: Icons.search_outlined,
                activeIcon: Icons.search_rounded,
                active: activeTab == AppNavTab.search,
                onTap: () => _handleTap(context, ref, AppNavTab.search),
              ),
              _NavItem(
                label: 'SETTINGS',
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings_rounded,
                active: activeTab == AppNavTab.settings,
                onTap: () => _handleTap(context, ref, AppNavTab.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppColors.secondary;
    final inactiveColor =
        isDark ? AppColors.textDisabledDark : AppColors.textSecondaryLight;
    final color = active ? activeColor : inactiveColor;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppNavBar._itemVerticalPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing dot indicator above active icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                width: active ? 6 : 0,
                height: active ? 6 : 0,
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? activeColor : Colors.transparent,
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
              Icon(
                active ? activeIcon : icon,
                color: color,
                size: AppNavBar._iconSize,
              ),
              const SizedBox(height: AppNavBar._iconLabelGap),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: AppNavBar._labelFontSize,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
