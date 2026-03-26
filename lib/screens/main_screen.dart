import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:showcaseview/showcaseview.dart';

import '../providers/home_tour_provider.dart';
import '../providers/main_tab_provider.dart';
import '../routing/app_routes.dart';
import '../theme/app_colors.dart';
import '../widgets/app_nav_bar.dart';
import '../widgets/app_showcase.dart';
import 'home/home_screen.dart';
import 'rooms/rooms_screen.dart';
import 'search/search_screen.dart';
import 'settings/settings_screen.dart';

/// Root shell for the four main tabs.
///
/// Wraps [HomeScreen], [RoomsScreen], [SearchScreen] and [SettingsScreen] in a
/// [PageView] so the user can swipe horizontally between them. A fixed
/// [AppNavBar] at the bottom stays in place during the swipe.
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late final PageController _pageController;
  final HomeTourShowcaseKeys _homeTourKeys = HomeTourShowcaseKeys();
  bool _homeTourQueued = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: ref.read(mainTabProvider),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // PageView <-> Provider sync

  void _onPageChanged(int index) {
    final current = ref.read(mainTabProvider);
    if (current != index) {
      ref.read(mainTabProvider.notifier).state = index;
    }
  }

  void _onNavTabTap(AppNavTab tab) {
    _pageController.animateToPage(
      tab.index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _startHomeTour(BuildContext context) async {
    if (_homeTourQueued) return;
    _homeTourQueued = true;
    final showcase = ShowCaseWidget.of(context);

    await ref.read(homeTourControllerProvider.notifier).markSeen();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (!mounted || ref.read(mainTabProvider) != AppNavTab.items.index) {
      return;
    }

    showcase.startShowCase([
      _homeTourKeys.fab,
      _homeTourKeys.searchBar,
      _homeTourKeys.dashboard,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(mainTabProvider);
    final activeTab = AppNavTab.values[currentIndex];
    final hasSeenHomeTour = ref.watch(homeTourControllerProvider);

    // Listen for programmatic tab changes (e.g. from a sub-screen that
    // sets mainTabProvider before calling context.go('/home')).
    ref.listen<int>(mainTabProvider, (prev, next) {
      if (_pageController.hasClients && _pageController.page?.round() != next) {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });

    return ShowCaseWidget(
      blurValue: 1.5,
      enableAutoScroll: true,
      globalTooltipActionConfig: appShowcaseTooltipActionConfig,
      globalTooltipActions: appShowcaseTooltipActions(),
      builder: (tourContext) {
        if (currentIndex == AppNavTab.items.index &&
            hasSeenHomeTour.valueOrNull == false &&
            !_homeTourQueued) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                _homeTourQueued ||
                ref.read(mainTabProvider) != AppNavTab.items.index) {
              return;
            }
            unawaited(_startHomeTour(tourContext));
          });
        }

        return Scaffold(
          body: Stack(
            children: [
              // Swipeable tab pages
              PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                children: [
                  _KeepAlive(child: HomeScreen(tourKeys: _homeTourKeys)),
                  const _KeepAlive(child: RoomsScreen()),
                  const _KeepAlive(child: SearchScreen(isEmbedded: true)),
                  const _KeepAlive(child: SettingsScreen()),
                ],
              ),

              // Fixed bottom nav bar
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AppNavBar(
                  activeTab: activeTab,
                  onTabChanged: _onNavTabTap,
                ),
              ),

              // Camera FAB, visible only on the Items tab
              if (currentIndex == AppNavTab.items.index)
                Positioned(
                  bottom: AppNavBar.fabBottom(context),
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Showcase(
                      key: _homeTourKeys.fab,
                      title: 'Start Here!',
                      description:
                          'Tap to save your first item, document, or memory.',
                      tooltipPosition: TooltipPosition.top,
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
                      tooltipBorderRadius: BorderRadius.circular(16),
                      targetBorderRadius: BorderRadius.circular(36),
                      targetPadding: const EdgeInsets.all(8),
                      overlayOpacity: 0.78,
                      disableDefaultTargetGestures: true,
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
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Keeps the child widget alive inside a [PageView] so its state is preserved
/// when the user swipes to another tab.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
