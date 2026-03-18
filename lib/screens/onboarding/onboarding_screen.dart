import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../providers/settings_provider.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _skip() {
    ref.read(settingsProvider.notifier).completeOnboarding();
    context.go(AppRoutes.home);
  }

  Future<void> _enableCamera() async {
    await Permission.camera.request();
    _goToPage(1);
  }

  void _getStarted() {
    ref.read(settingsProvider.notifier).completeOnboarding();
    context.go(AppRoutes.home);
  }

  void _goToPage(int page) {
    setState(() => _currentPage = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: TextButton(
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: AppColors.primary.withValues(alpha: 0.8),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),

            // ── Pages ─────────────────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _WelcomePage(
                      textPrimary: textPrimary, textSecondary: textSecondary),
                  _AllSetPage(
                      textPrimary: textPrimary, textSecondary: textSecondary),
                ],
              ),
            ),

            // ── Bottom Action Area ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(2, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: isActive ? 24 : 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 28),

                  // CTA button
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _currentPage == 0
                        ? Column(
                            key: const ValueKey('page0-actions'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PrimaryButton(
                                icon: Icons.photo_camera_rounded,
                                label: 'Enable Camera',
                                onTap: _enableCamera,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Required to scan items and recognize your storage spaces instantly. No images are uploaded without your permission.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          )
                        : _PrimaryButton(
                            key: const ValueKey('page1-actions'),
                            icon: Icons.arrow_forward_rounded,
                            label: 'Get Started',
                            onTap: _getStarted,
                          ),
                  ),
                ],
              ),
            ),

            // ── Bottom gradient line ───────────────────────────────────────────
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    AppColors.primary.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 1: Welcome ───────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({
    required this.textPrimary,
    required this.textSecondary,
  });

  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final illustrationHeight =
        (screenHeight * 0.32).clamp(220.0, 300.0).toDouble();
    final sectionSpacing = screenHeight < 760 ? 24.0 : 36.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration
          _IllustrationCard(height: illustrationHeight)
              .animate()
              .fadeIn(duration: 500.ms)
              .slideY(
                  begin: 0.06, end: 0, duration: 500.ms, curve: Curves.easeOut),

          SizedBox(height: sectionSpacing),

          // Text
          Text(
            'Never lose track of\nyour things.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.2,
            ),
          ).animate(delay: 100.ms).fadeIn(duration: 400.ms).slideY(
              begin: 0.05, end: 0, duration: 400.ms, curve: Curves.easeOut),

          const SizedBox(height: 14),

          Text(
            'Save in 10 seconds, find in 5.\nOrganize your life visually.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textSecondary,
              fontSize: 17,
              height: 1.55,
            ),
          ).animate(delay: 180.ms).fadeIn(duration: 400.ms).slideY(
              begin: 0.05, end: 0, duration: 400.ms, curve: Curves.easeOut),
        ],
      ),
    );
  }
}

// ── Page 2: All Set ───────────────────────────────────────────────────────────

class _AllSetPage extends StatelessWidget {
  const _AllSetPage({
    required this.textPrimary,
    required this.textSecondary,
  });

  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final illustrationHeight =
        (screenHeight * 0.32).clamp(220.0, 300.0).toDouble();
    final sectionSpacing = screenHeight < 760 ? 24.0 : 36.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration
          _IllustrationCard(
            icon: Icons.check_circle_rounded,
            height: illustrationHeight,
          ).animate().fadeIn(duration: 500.ms).scale(
              begin: const Offset(0.92, 0.92),
              end: const Offset(1, 1),
              duration: 500.ms,
              curve: Curves.easeOut),

          SizedBox(height: sectionSpacing),

          Text(
            "You're all set!",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.2,
            ),
          ).animate(delay: 100.ms).fadeIn(duration: 400.ms),

          const SizedBox(height: 14),

          Text(
            'Start by photographing an item and telling Ikeep where it lives.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textSecondary,
              fontSize: 17,
              height: 1.55,
            ),
          ).animate(delay: 180.ms).fadeIn(duration: 400.ms),
        ],
      ),
    );
  }
}

// ── Illustration Card ─────────────────────────────────────────────────────────

class _IllustrationCard extends StatelessWidget {
  const _IllustrationCard({
    this.icon = Icons.inventory_2_rounded,
    this.height = 300,
  });

  final IconData icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          // Decorative circle (top-left)
          Positioned(
            top: 28,
            left: 28,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  width: 2,
                ),
              ),
            ),
          ),

          // Decorative rotated rectangle (bottom-right)
          Positioned(
            bottom: 24,
            right: 24,
            child: Transform.rotate(
              angle: 0.21, // ~12 degrees
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // Faded search icon overlay (top-right)
          Positioned(
            top: -8,
            right: -8,
            child: Icon(
              Icons.search_rounded,
              size: 120,
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),

          // Main icon
          Center(
            child: Icon(
              icon,
              size: 96,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared: Primary Button ────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          shadowColor: AppColors.primary.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
