import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'providers/auth_providers.dart';
import 'providers/app_update_providers.dart';
import 'providers/restore_provider.dart';
import 'providers/service_providers.dart';
import 'providers/settings_provider.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';
import 'widgets/force_update_screen.dart';

class IkeepApp extends ConsumerStatefulWidget {
  const IkeepApp({super.key});

  @override
  ConsumerState<IkeepApp> createState() => _IkeepAppState();
}

class _IkeepAppState extends ConsumerState<IkeepApp>
    with WidgetsBindingObserver {
  /// Tracks the last-observed Firebase UID so we can detect sign-in / sign-out
  /// transitions and trigger the appropriate restore action.
  String? _lastAuthUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Silently restore Firebase auth from a cached Google account (if any).
    unawaited(ref.read(authSessionBootstrapProvider.future));
    // Backfill hierarchical location UUIDs on items that predate Phase-1.
    unawaited(ref.read(locationHierarchyMigrationProvider.future));
    // Prime app update state at startup — deferred to after the first frame
    // to avoid synchronous state mutations during the initial build phase,
    // which would trigger the '!_dirty' assertion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(appUpdateControllerProvider.notifier).initialize());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(
      ref.read(appUpdateControllerProvider.notifier).checkForUpdates(
            reason: AppUpdateCheckReason.appResume,
          ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called whenever the Firebase auth state emits a new [User?] value.
  ///
  /// On a fresh install the local SQLite database is empty. When the user
  /// signs in [AutoRestoreNotifier.checkAndRestore] detects whether a remote
  /// backup exists and — if so — runs a full sync automatically. No manual
  /// "Sync" button tap required.
  void _handleAuthStateChange(User? previous, User? current) {
    final currentUid = current?.uid;

    if (currentUid == _lastAuthUid) return; // State unchanged — ignore.

    if (currentUid != null && _lastAuthUid == null) {
      // User just signed in (or was restored from a cached account).
      // Trigger auto-restore on fresh installs.
      unawaited(
        ref.read(autoRestoreProvider.notifier).checkAndRestore(),
      );
    } else if (currentUid == null && _lastAuthUid != null) {
      // User signed out — reset the restore state so the next sign-in can
      // trigger the flow again (important when switching Google accounts).
      ref.read(autoRestoreProvider.notifier).reset();
    }

    _lastAuthUid = currentUid;
  }

  Future<void> _handleGlobalForceUpdateTap() async {
    final result = await ref
        .read(appUpdateControllerProvider.notifier)
        .runPrimaryUpdateAction();
    if (!mounted) return;

    if (result.shouldOpenStore) {
      await _openPlayStoreForForceUpdate();
      return;
    }

    if (result.action == UpdateNowActionKind.failed ||
        result.action == UpdateNowActionKind.userDenied) {
      _showForceUpdateInfo(result.message ?? 'Unable to start update');
    }
  }

  Future<void> _openPlayStoreForForceUpdate() async {
    final playStoreUrl =
        ref.read(effectiveAppUpdateDecisionProvider).playStoreUrl.trim();
    final uri = Uri.tryParse(playStoreUrl);
    if (uri == null) {
      _showForceUpdateInfo('Play Store link is invalid');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || opened) return;
    _showForceUpdateInfo('Unable to open Google Play');
  }

  void _showForceUpdateInfo(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _exitApp() {
    if (!Platform.isAndroid) return;
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    // Listen to auth state changes to drive the auto-restore flow.
    // We use ref.listen here (not ref.watch) because we only want the
    // side-effect — we do not need to rebuild when auth changes.
    ref.listen<AsyncValue<User?>>(
      authStateProvider,
      (previous, next) {
        _handleAuthStateChange(
          previous?.valueOrNull,
          next.valueOrNull,
        );
      },
    );

    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);
    final updateState = ref.watch(appUpdateControllerProvider);
    final updateDecision = updateState.decision;

    return MaterialApp.router(
      title: 'Ikeep',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF040124),
                      const Color(0xFF130A38),
                      const Color(0xFF0C0A20)
                    ]
                  : [
                      const Color(0xFFF7F5FC),
                      const Color(0xFFEBE6F5),
                      const Color(0xFFFFFFFF)
                    ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (updateDecision.isForceUpdate)
                Positioned.fill(
                  child: ForceUpdateScreen(
                    decision: updateDecision,
                    isActionInProgress: updateState.isUpdateActionInProgress,
                    onUpdateNow: _handleGlobalForceUpdateTap,
                    onExitApp: _exitApp,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
