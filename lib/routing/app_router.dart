import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/detail/item_detail_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/rooms/rooms_screen.dart';
import '../screens/save/save_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../providers/settings_provider.dart';
import 'app_routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final settings = ref.watch(settingsProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final onboardingDone = settings.isOnboardingComplete;
      final isOnboarding = state.uri.path == AppRoutes.onboarding;

      if (!onboardingDone && !isOnboarding) return AppRoutes.onboarding;
      if (onboardingDone && state.uri.path == AppRoutes.splash) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const HomeScreen(), // redirected by above
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.save,
        builder: (context, state) => const SaveScreen(),
      ),
      GoRoute(
        path: AppRoutes.itemDetail,
        builder: (context, state) {
          final uuid = state.pathParameters['uuid']!;
          return ItemDetailScreen(uuid: uuid);
        },
      ),
      GoRoute(
        path: AppRoutes.rooms,
        builder: (context, state) => const RoomsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) {
          final initial = state.extra as String? ?? '';
          return SearchScreen(initialQuery: initial);
        },
      ),
    ],
  );
});
