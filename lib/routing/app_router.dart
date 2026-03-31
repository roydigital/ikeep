import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/detail/item_detail_screen.dart';
import '../screens/home/dashboard_items_screen.dart';
import '../screens/main_screen.dart';
import '../screens/save/quick_add_multiple_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/save/save_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/settings/household_settings_screen.dart';
import '../providers/settings_provider.dart';
import '../widgets/swipe_back_wrapper.dart';
import 'app_routes.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

/// Slide-from-right page with swipe-back gesture for sub-screens.
CustomTransitionPage<void> _swipeBackPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: SwipeBackWrapper(child: child),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: child,
      );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);
  ref.listen<AppSettings>(settingsProvider, (previous, next) {
    if (previous?.isOnboardingComplete != next.isOnboardingComplete) {
      refreshNotifier.refresh();
    }
  });

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final settings = ref.read(settingsProvider);
      final onboardingDone = settings.isOnboardingComplete;
      final isOnboarding = state.uri.path == AppRoutes.onboarding;

      if (!onboardingDone && !isOnboarding) return AppRoutes.onboarding;
      if (onboardingDone && state.uri.path == AppRoutes.splash) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const MainScreen(), // redirected
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),

      // ── Main tab shell (Items / Locations / Search / Settings) ─────
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const MainScreen(),
      ),

      // ── Sub-routes (slide-from-right + swipe-back) ─────────────────
      GoRoute(
        path: AppRoutes.save,
        pageBuilder: (context, state) {
          final extra = state.extra;
          final initialZoneUuid = extra is Map<String, dynamic>
              ? extra['initialZoneUuid'] as String?
              : null;
          return _swipeBackPage(
            key: state.pageKey,
            child: SaveScreen(initialZoneUuid: initialZoneUuid),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.zoneQuickAdd,
        pageBuilder: (context, state) => _swipeBackPage(
          key: state.pageKey,
          child: QuickAddMultipleScreen(
            zoneUuid: state.pathParameters['zoneUuid']!,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.itemDetail,
        pageBuilder: (context, state) => _swipeBackPage(
          key: state.pageKey,
          child: ItemDetailScreen(uuid: state.pathParameters['uuid']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.manageFamily,
        pageBuilder: (context, state) => _swipeBackPage(
          key: state.pageKey,
          child: const HouseholdSettingsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.search,
        pageBuilder: (context, state) {
          final extra = state.extra;
          final Widget screen;
          if (extra is Map<String, dynamic>) {
            screen = SearchScreen(
              initialQuery: extra['initialQuery'] as String? ?? '',
              initialLocationUuid: extra['initialLocationUuid'] as String?,
            );
          } else {
            final initial = extra as String? ?? '';
            screen = SearchScreen(initialQuery: initial);
          }
          return _swipeBackPage(key: state.pageKey, child: screen);
        },
      ),

      // ── Dashboard drill-down routes ────────────────────────────────
      GoRoute(
        path: AppRoutes.dashboardLentOut,
        pageBuilder: (context, state) => _swipeBackPage(
          key: state.pageKey,
          child: const DashboardItemsScreen(
            mode: DashboardItemsMode.lentOut,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.dashboardExpiringSoon,
        pageBuilder: (context, state) => _swipeBackPage(
          key: state.pageKey,
          child: const DashboardItemsScreen(
            mode: DashboardItemsMode.expiringSoon,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.dashboardWarrantyEnding,
        pageBuilder: (context, state) => _swipeBackPage(
          key: state.pageKey,
          child: const DashboardItemsScreen(
            mode: DashboardItemsMode.warrantyEndingSoon,
          ),
        ),
      ),
    ],
  );
});
