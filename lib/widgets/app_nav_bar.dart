import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../routing/app_routes.dart';
import '../theme/app_colors.dart';

/// Which main tab is currently active.
enum AppNavTab { items, locations, search, settings }

/// Shared bottom navigation bar used across all main screens.
/// Visual style is identical to the Rooms & Zones screen (the app's native theme):
///  • Dark background  • Primary-accented top border  • ALL-CAPS bold labels
///  • 27 px icons  • 10.5 px labels with letter-spacing 1
class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.activeTab});

  final AppNavTab activeTab;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, 10, 8, bottomInset + 10),
          decoration: BoxDecoration(
            color:
                (isDark ? AppColors.backgroundDark : AppColors.backgroundLight)
                    .withValues(alpha: 0.75),
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
                active: activeTab == AppNavTab.items,
                onTap: () {
                  if (activeTab != AppNavTab.items) context.go(AppRoutes.home);
                },
              ),
              _NavItem(
                label: 'LOCATIONS',
                icon: Icons.location_on,
                active: activeTab == AppNavTab.locations,
                onTap: () {
                  if (activeTab != AppNavTab.locations)
                    context.go(AppRoutes.rooms);
                },
              ),
              _NavItem(
                label: 'SEARCH',
                icon: Icons.search,
                active: activeTab == AppNavTab.search,
                onTap: () {
                  if (activeTab != AppNavTab.search)
                    context.push(AppRoutes.search);
                },
              ),
              _NavItem(
                label: 'SETTINGS',
                icon: Icons.settings,
                active: activeTab == AppNavTab.settings,
                onTap: () {
                  if (activeTab != AppNavTab.settings) {
                    context.go(AppRoutes.settings);
                  }
                },
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
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);
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
