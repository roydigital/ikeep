import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/feature_limits.dart';
import '../../domain/models/item.dart';
import '../../domain/models/cloud_entitlement.dart';
import '../../domain/models/sync_status.dart';
import '../../providers/auth_providers.dart';
import '../../providers/home_tour_provider.dart';
import '../../providers/item_providers.dart';
import '../../providers/main_tab_provider.dart';
import '../../providers/location_providers.dart';
import '../../providers/restore_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_providers.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_nav_bar.dart';
import '../../widgets/app_showcase.dart';
import 'cloud_diagnostics_screen.dart';

const _kAccent = AppColors.primary;

class _SettingsColors {
  const _SettingsColors({
    required this.bg,
    required this.card,
    required this.cardSoft,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.icon,
    required this.success,
    required this.switchOffTrack,
    required this.switchOffThumb,
  });

  final Color bg;
  final Color card;
  final Color cardSoft;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color icon;
  final Color success;
  final Color switchOffTrack;
  final Color switchOffThumb;
}

const _darkColors = _SettingsColors(
  bg: AppColors.backgroundDark,
  card: AppColors.surfaceDark,
  cardSoft: AppColors.surfaceVariantDark,
  border: AppColors.borderDark,
  textPrimary: AppColors.textPrimaryDark,
  textMuted: AppColors.textSecondaryDark,
  icon: AppColors.textSecondaryDark,
  success: AppColors.success,
  switchOffTrack: AppColors.surfaceVariantDark,
  switchOffThumb: AppColors.textDisabledDark,
);

const _lightColors = _SettingsColors(
  bg: AppColors.backgroundLight,
  card: AppColors.surfaceLight,
  cardSoft: AppColors.surfaceVariantLight,
  border: AppColors.borderLight,
  textPrimary: AppColors.textPrimaryLight,
  textMuted: AppColors.textSecondaryLight,
  icon: AppColors.textSecondaryLight,
  success: AppColors.success,
  switchOffTrack: AppColors.surfaceVariantLight,
  switchOffThumb: AppColors.surfaceLight,
);

late _SettingsColors _activeColors;

Color get _kBg => _activeColors.bg;
Color get _kCard => _activeColors.card;
Color get _kCardSoft => _activeColors.cardSoft;
Color get _kBorder => _activeColors.border;
Color get _kTextPrimary => _activeColors.textPrimary;
Color get _kTextMuted => _activeColors.textMuted;
Color get _kSuccess => _activeColors.success;
Color get _kIcon => _activeColors.icon;
Color get _kSwitchOffTrack => _activeColors.switchOffTrack;
Color get _kSwitchOffThumb => _activeColors.switchOffThumb;

Widget _buildSettingsTourStep({
  required GlobalKey showcaseKey,
  required String title,
  required String description,
  required Widget child,
  TooltipPosition? tooltipPosition,
}) {
  return Showcase(
    key: showcaseKey,
    title: title,
    description: description,
    tooltipPosition: tooltipPosition,
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
    targetBorderRadius: BorderRadius.circular(28),
    targetPadding: const EdgeInsets.all(6),
    overlayOpacity: 0.78,
    disableDefaultTargetGestures: true,
    child: child,
  );
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static final Uri _helpCenterUri =
      Uri.parse('https://roydigital.in/ikeep/help-center.html');
  static final Uri _contactUsUri =
      Uri.parse('https://roydigital.in/ikeep/contact-us.html');
  static final Uri _termsPrivacyUri =
      Uri.parse('https://roydigital.in/ikeep/terms-privacy.html');
  static final Uri _accountDeletionUri =
      Uri.parse('https://roydigital.in/ikeep/delete-account.html');

  bool _initialized = false;
  bool _darkMode = true;
  bool _stillThere = true;
  bool _seasonal = true;
  bool _lentReminders = true;
  bool _backupEnabled = false;
  bool _isSaving = false;
  bool _isSigningIn = false;
  bool _isLoggingOut = false;
  bool _canLoadRemoteSyncMetadata = false;
  String? _lastObservedAuthUid;
  Timer? _remoteSyncMetadataTimer;
  final GlobalKey _accountShowcaseKey = GlobalKey();
  final GlobalKey _preferencesShowcaseKey = GlobalKey();
  final GlobalKey _cloudFeaturesShowcaseKey = GlobalKey();
  bool _settingsTourQueued = false;

  @override
  void initState() {
    super.initState();
    final initialAuthUid = ref.read(firebaseAuthProvider).currentUser?.uid;
    _lastObservedAuthUid = initialAuthUid;
    _canLoadRemoteSyncMetadata = initialAuthUid != null;
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isSigningIn = true);
    final googleSignIn = ref.read(googleSignInProvider);
    final auth = ref.read(firebaseAuthProvider);

    try {
      final account = await runInteractiveGoogleSignInFlow(
        () async {
          final selectedAccount = await googleSignIn.signIn();
          if (selectedAccount != null) {
            await signInFirebaseWithGoogleAccount(auth, selectedAccount);
          }
          return selectedAccount;
        },
      );
      if (!mounted) return;
      setState(() => _isSigningIn = false);
      if (account == null) {
        _showInfo('Google sign-in cancelled');
      } else {
        _enableRemoteSyncMetadataNow();
        final syncResult =
            await ref.read(autoRestoreProvider.notifier).syncAfterSignIn();
        if (!mounted) return;
        if (syncResult.isSyncing) {
          _showInfo('Signed in. Your cloud backup is syncing now');
        } else {
          _showInfo('Signed in. ${_syncResultMessage(syncResult)}');
        }
      }
    } catch (e, st) {
      debugPrint('Google sign-in failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() => _isSigningIn = false);
      _showInfo('Unable to sign in with Google');
    }
  }

  Future<void> _handleLogout() async {
    setState(() => _isLoggingOut = true);
    final auth = ref.read(firebaseAuthProvider);
    final googleSignIn = ref.read(googleSignInProvider);

    try {
      await auth.signOut();
      await googleSignIn.signOut();
      if (!mounted) return;
      setState(() => _isLoggingOut = false);
      _showInfo('Logged out');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoggingOut = false);
      _showInfo('Unable to log out');
    }
  }

  void _initFromSettings(AppSettings settings) {
    if (_initialized) return;
    _darkMode = settings.themeMode == ThemeMode.dark;
    _stillThere = settings.stillThereRemindersEnabled;
    _seasonal = settings.seasonalRemindersEnabled;
    _lentReminders = settings.lentRemindersEnabled;
    _backupEnabled = settings.isBackupEnabled;
    _initialized = true;
  }

  bool _hasChanges(AppSettings settings) {
    return _darkMode != (settings.themeMode == ThemeMode.dark) ||
        _stillThere != settings.stillThereRemindersEnabled ||
        _seasonal != settings.seasonalRemindersEnabled ||
        _lentReminders != settings.lentRemindersEnabled ||
        _backupEnabled != settings.isBackupEnabled;
  }

  Future<void> _toggleDarkMode(bool enabled) async {
    setState(() => _darkMode = enabled);
    await ref
        .read(settingsProvider.notifier)
        .setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> _save(AppSettings settings) async {
    if (_isSaving || !_hasChanges(settings)) return;
    setState(() => _isSaving = true);
    try {
      final notifier = ref.read(settingsProvider.notifier);
      final notificationService = ref.read(notificationServiceProvider);
      final backgroundScheduler = ref.read(backgroundSchedulerServiceProvider);
      final wantsNotificationFeatures = settings.expiryRemindersEnabled ||
          _stillThere ||
          _seasonal ||
          _lentReminders;

      if (wantsNotificationFeatures) {
        final permissionGranted =
            await notificationService.requestPermissionsIfNeeded();
        if (!permissionGranted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Notifications are off. Reminders can be saved, but alerts may not appear until permission is allowed.',
              ),
            ),
          );
        }
      }

      await notifier.setThemeMode(_darkMode ? ThemeMode.dark : ThemeMode.light);
      await notifier.setStillThereReminders(_stillThere);
      await notifier.setSeasonalReminders(_seasonal);
      await notifier.setLentReminders(_lentReminders);
      await notifier.setBackupEnabled(_backupEnabled);

      final updatedSettings = settings.copyWith(
        themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
        stillThereRemindersEnabled: _stillThere,
        seasonalRemindersEnabled: _seasonal,
        lentRemindersEnabled: _lentReminders,
        isBackupEnabled: _backupEnabled,
      );
      await backgroundScheduler.syncNotificationTasks(updatedSettings);

      try {
        final items = await ref.read(allItemsProvider.future);
        await notificationService.rescheduleExpiryReminders(
          items.where((item) => !item.isArchived),
        );

        if (_lentReminders) {
          await notificationService.rescheduleLentReminders(
            items.where((item) => item.isLent && !item.isArchived),
          );
        } else {
          for (final item in items) {
            await notificationService.cancelLentReminder(item.uuid);
          }
        }
      } catch (_) {
        // Items couldn't be loaded — notification sync will catch up on
        // next app launch via background scheduler.
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update notification settings')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _runSync() async {
    // Prevent double-sync if auto-sync after sign-in is already running.
    final currentStatus = ref.read(syncStatusProvider);
    if (currentStatus.isSyncing) {
      _showInfo('A sync is already in progress');
      return;
    }

    final auth = ref.read(firebaseAuthProvider);
    if (auth.currentUser == null) {
      _showInfo('Sign in with Google to sync your cloud backup');
      return;
    }

    if (!_backupEnabled) {
      await ref.read(settingsProvider.notifier).setBackupEnabled(true);
      if (mounted) {
        setState(() => _backupEnabled = true);
      }
    }

    _enableRemoteSyncMetadataNow();
    ref.read(syncStatusProvider.notifier).state = const SyncResult.syncing();
    final result = await ref.read(syncServiceProvider).syncAll();
    ref.read(syncStatusProvider.notifier).state = result;
    ref.invalidate(lastSyncedAtProvider);
    ref.invalidate(allItemsProvider);
    ref.invalidate(backedUpItemsProvider);
    ref.invalidate(backedUpItemsCountProvider);
    ref.invalidate(allLocationsProvider);
    ref.invalidate(rootLocationsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_syncResultMessage(result))));
  }

  String _syncResultMessage(SyncResult result) {
    if (result.isTimedOut) {
      return 'Sync timed out — ${result.syncedItems} of '
          '${result.totalItems} items synced';
    }
    if (result.hasError) {
      return result.errorMessage ?? 'Sync failed';
    }
    // Success path — show counts when there were items to sync.
    if (result.totalItems == 0) {
      return 'Everything is up to date';
    }
    final buffer = StringBuffer('Sync completed');
    if (result.failedItems > 0) {
      buffer.write(' — ${result.syncedItems}/${result.totalItems} items synced'
          ', ${result.failedItems} failed');
    } else if (result.partialFailure) {
      buffer.write(' — some attachments could not be uploaded');
    }
    return buffer.toString();
  }

  Future<void> _exportData() async {
    if (!_backupEnabled) {
      _showInfo('Enable cloud backup on an item to export your data');
      return;
    }

    final colors = _darkMode ? _darkColors : _lightColors;
    try {
      final items = await ref.read(allItemsProvider.future);
      final locations = await ref.read(allLocationsProvider.future);

      final exportedItems = <Map<String, dynamic>>[];
      for (final item in items) {
        final imageExports = <Map<String, dynamic>>[];
        for (final imagePath in item.imagePaths) {
          String? base64Data;
          try {
            final file = File(imagePath);
            if (await file.exists()) {
              base64Data = base64Encode(await file.readAsBytes());
            }
          } catch (_) {
            base64Data = null;
          }

          imageExports.add({
            'path': imagePath,
            'fileName': imagePath.split(RegExp(r'[/\\]')).last,
            'base64': base64Data,
          });
        }

        exportedItems.add({
          ...item.toJson(),
          'locationName': item.locationName,
          'locationFullPath': item.locationFullPath,
          'isArchived': item.isArchived,
          'images': imageExports,
        });
      }

      final payload = {
        'exportedAt': DateTime.now().toIso8601String(),
        'formatVersion': 1,
        'itemsCount': items.length,
        'locationsCount': locations.length,
        'items': exportedItems,
        'locations': locations.map((e) => e.toJson()).toList(),
      };

      final exportJson = const JsonEncoder.withIndent('  ').convert(payload);
      final exportDir = await getApplicationDocumentsDirectory();
      final fileName =
          'ikeep_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
      final file = File('${exportDir.path}/$fileName');
      await file.writeAsString(exportJson);

      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: colors.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title:
              Text('Export Ready', style: TextStyle(color: colors.textPrimary)),
          content: Text(
            'Downloaded $fileName with ${items.length} items, ${locations.length} locations, and image data.',
            style: TextStyle(color: colors.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(color: _kAccent)),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export data')),
      );
    }
  }

  Future<void> _openCloudDiagnostics() async {
    final planMode = ref.read(cloudEntitlementModeProvider);
    if (planMode != CloudEntitlementMode.closedTestingFreeAccess) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return const FractionallySizedBox(
          heightFactor: 0.94,
          child: CloudDiagnosticsPanel(),
        );
      },
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSupportPage(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || opened) return;
    _showInfo('Unable to open support page');
  }

  String _formatLastSynced(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    final now = DateTime.now();
    final isToday = now.year == dateTime.year &&
        now.month == dateTime.month &&
        now.day == dateTime.day;
    if (isToday) {
      return 'Today, ${DateFormat('h:mm a').format(dateTime)}';
    }
    return DateFormat('MMM d, h:mm a').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    _initFromSettings(settings);
    _activeColors = _darkMode ? _darkColors : _lightColors;
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final authUid = authUser?.uid;
    if (authUid != _lastObservedAuthUid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleAuthUidChange(authUid);
      });
    }
    final hasSeenSettingsTour = ref.watch(settingsTourControllerProvider);
    // Only start the tour when the Settings tab (index 3) is actually visible.
    final activeTab = ref.watch(mainTabProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final backedUpCountAsync = ref.watch(backedUpItemsCountProvider);
    final backedUpCount = backedUpCountAsync.valueOrNull ?? 0;
    final backedUpItemsAsync = ref.watch(backedUpItemsProvider);
    final backedUpItems = backedUpItemsAsync.valueOrNull ?? const <Item>[];
    final hasBackedUpItems = backedUpCount > 0;
    final backupEnabled = _backupEnabled || hasBackedUpItems;
    final shouldLoadLastSynced = authUser != null && _canLoadRemoteSyncMetadata;
    final lastSynced = shouldLoadLastSynced
        ? ref.watch(lastSyncedAtProvider).valueOrNull
        : syncStatus.lastSyncedAt;

    final canSave = _hasChanges(settings) && !_isSaving;
    final isGoogleSignedIn = authUser != null;
    final showLogoutAction = isGoogleSignedIn || _isLoggingOut;
    final hasCloudConnection =
        authUser != null && (backupEnabled || lastSynced != null);
    final statusColor = authUser == null
        ? _kTextMuted
        : syncStatus.hasError
            ? AppColors.error
            : hasCloudConnection
                ? _kSuccess
                : _kAccent;
    final statusText = authUser == null
        ? 'Sign In'
        : syncStatus.isSyncing
            ? 'Syncing...'
            : syncStatus.isTimedOut
                ? 'Timed Out'
                : syncStatus.hasError
                    ? 'Error'
                    : hasCloudConnection
                        ? 'Connected'
                        : 'Ready to Sync';
    final lastSyncedText = authUser != null && !_canLoadRemoteSyncMetadata
        ? 'Loading...'
        : _formatLastSynced(lastSynced);
    return ShowCaseWidget(
      blurValue: 1.5,
      enableAutoScroll: true,
      globalTooltipActionConfig: appShowcaseTooltipActionConfig,
      globalTooltipActions: appShowcaseTooltipActions(),
      builder: (tourContext) {
        if (activeTab == AppNavTab.settings.index &&
            hasSeenSettingsTour.valueOrNull == false &&
            !_settingsTourQueued) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _settingsTourQueued) return;
            _settingsTourQueued = true;
            ShowCaseWidget.of(tourContext).startShowCase([
              _accountShowcaseKey,
              _preferencesShowcaseKey,
              _cloudFeaturesShowcaseKey,
            ]);
            ref.read(settingsTourControllerProvider.notifier).markSeen();
          });
        }

        return Scaffold(
          backgroundColor: _kBg,
          body: Stack(
            children: [
              SafeArea(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Header(
                        canSave: canSave,
                        isSaving: _isSaving,
                        onBack: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(AppRoutes.home);
                          }
                        },
                        onSave: () => _save(settings),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        24,
                        20,
                        AppNavBar.contentBottomSpacing(context),
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(
                          [
                            _SectionLabel('ACCOUNT'),
                            const SizedBox(height: 14),
                            _buildSettingsTourStep(
                              showcaseKey: _accountShowcaseKey,
                              title: 'Your Account',
                              description:
                                  'Connect your account, confirm your membership status, and see whether backup is active.',
                              tooltipPosition: TooltipPosition.bottom,
                              child: _AccountCard(
                                backupEnabled: backupEnabled,
                                backedUpCount: backedUpCount,
                                backedUpItemNames: backedUpItems
                                    .map((item) => item.name)
                                    .toList(),
                                isUsageLoading: backedUpCountAsync.isLoading,
                                displayName: authUser?.displayName,
                                photoUrl: authUser?.photoURL,
                                isGoogleSignedIn: isGoogleSignedIn,
                                isSigningIn: _isSigningIn,
                                onGoogleSignInTap: !isGoogleSignedIn
                                    ? _handleGoogleSignIn
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 36),
                            _SectionLabel('PREFERENCES'),
                            const SizedBox(height: 14),
                            _buildSettingsTourStep(
                              showcaseKey: _preferencesShowcaseKey,
                              title: 'Tune Your Preferences',
                              description:
                                  'Adjust theme and reminder behavior here so Ikeep matches how you actually use it.',
                              tooltipPosition: TooltipPosition.top,
                              child: _PreferencesCard(
                                darkMode: _darkMode,
                                stillThere: _stillThere,
                                seasonal: _seasonal,
                                lentReminders: _lentReminders,
                                onDarkModeChanged: _toggleDarkMode,
                                onStillThereChanged: (v) =>
                                    setState(() => _stillThere = v),
                                onSeasonalChanged: (v) =>
                                    setState(() => _seasonal = v),
                                onLentRemindersChanged: (v) =>
                                    setState(() => _lentReminders = v),
                              ),
                            ),
                            const SizedBox(height: 36),
                            _SectionLabel('CLOUD & FAMILY'),
                            const SizedBox(height: 14),
                            _buildSettingsTourStep(
                              showcaseKey: _cloudFeaturesShowcaseKey,
                              title: 'Backup And Family Features',
                              description:
                                  'Monitor sync status, trigger a backup, and manage family-sharing features from this card.',
                              tooltipPosition: TooltipPosition.top,
                              child: _CloudAndFamilyCard(
                                statusText: statusText,
                                statusColor: statusColor,
                                isSyncing: syncStatus.isSyncing,
                                progress: backupEnabled ? 0.85 : 0.4,
                                lastSyncedText: lastSyncedText,
                                onSyncTap: syncStatus.isSyncing
                                    ? null
                                    : _runSync,
                                onManageFamily: () =>
                                    context.push(AppRoutes.manageFamily),
                              ),
                            ),
                            const SizedBox(height: 36),
                            _SectionLabel('SUPPORT'),
                            const SizedBox(height: 14),
                            _SupportCard(
                              onHelp: () => _openSupportPage(_helpCenterUri),
                              onContact: () => _openSupportPage(_contactUsUri),
                              onTerms: () => _openSupportPage(_termsPrivacyUri),
                              onDeleteAccount: () =>
                                  _openSupportPage(_accountDeletionUri),
                            ),
                            const SizedBox(height: 52),
                            Center(
                              child: GestureDetector(
                                onLongPress: _openCloudDiagnostics,
                                child: Text(
                                  AppConstants.buildLabel,
                                  style: TextStyle(
                                    color: _kTextMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            if (showLogoutAction) ...[
                              const SizedBox(height: 18),
                              Center(
                                child: _isLoggingOut
                                    ? Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.error
                                                    .withValues(alpha: 0.7),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              'Logging out...',
                                              style: TextStyle(
                                                color: AppColors.error,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: _handleLogout,
                                        child: const Text(
                                          'Log Out',
                                          style: TextStyle(
                                            color: AppColors.error,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleAuthUidChange(String? authUid) {
    _remoteSyncMetadataTimer?.cancel();
    final previousUid = _lastObservedAuthUid;
    _lastObservedAuthUid = authUid;

    if (authUid == null) {
      if (_canLoadRemoteSyncMetadata) {
        setState(() => _canLoadRemoteSyncMetadata = false);
      }
      return;
    }

    if (previousUid == null) {
      if (_canLoadRemoteSyncMetadata) {
        setState(() => _canLoadRemoteSyncMetadata = false);
      }
      _remoteSyncMetadataTimer = Timer(
        const Duration(milliseconds: 450),
        () {
          if (!mounted || _lastObservedAuthUid != authUid) return;
          setState(() => _canLoadRemoteSyncMetadata = true);
          ref.invalidate(lastSyncedAtProvider);
        },
      );
      return;
    }

    _enableRemoteSyncMetadataNow();
  }

  void _enableRemoteSyncMetadataNow() {
    _remoteSyncMetadataTimer?.cancel();
    if (!_canLoadRemoteSyncMetadata) {
      setState(() => _canLoadRemoteSyncMetadata = true);
    }
  }

  @override
  void dispose() {
    _remoteSyncMetadataTimer?.cancel();
    super.dispose();
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.canSave,
    required this.isSaving,
    required this.onBack,
    required this.onSave,
  });

  final bool canSave;
  final bool isSaving;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorder, width: 0.8)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(Icons.arrow_back, color: _kTextPrimary, size: 28),
          ),
          Text(
            'Settings',
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: canSave ? onSave : null,
            child: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: _kAccent,
                      strokeWidth: 2.1,
                    ),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      color: canSave ? _kAccent : _kTextMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: _kAccent,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        fontSize: 13,
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.backupEnabled,
    required this.backedUpCount,
    required this.backedUpItemNames,
    required this.isUsageLoading,
    required this.displayName,
    required this.photoUrl,
    required this.isGoogleSignedIn,
    this.onGoogleSignInTap,
    this.isSigningIn = false,
  });

  final bool backupEnabled;
  final int backedUpCount;
  final List<String> backedUpItemNames;
  final bool isUsageLoading;
  final String? displayName;
  final String? photoUrl;
  final bool isGoogleSignedIn;
  final Future<void> Function()? onGoogleSignInTap;
  final bool isSigningIn;

  @override
  Widget build(BuildContext context) {
    final isGuestUser =
        displayName == null || displayName!.trim().isEmpty || !isGoogleSignedIn;
    final googleSignInTap = onGoogleSignInTap;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Row(
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kCardSoft,
                    border: Border.all(color: _kBorder, width: 2),
                  ),
                  child: ClipOval(
                    child: photoUrl != null && photoUrl!.isNotEmpty
                        ? Image.network(
                            photoUrl!,
                            width: 74,
                            height: 74,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.person,
                            color: Color(0xFF9A8E76), size: 42),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isGuestUser ? 'Guest User' : displayName!,
                        style: TextStyle(
                          color: _kTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (isSigningIn)
                        Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _kAccent.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Signing in...',
                              style:
                                  TextStyle(color: _kTextMuted, fontSize: 14),
                            ),
                          ],
                        )
                      else if (!isGoogleSignedIn && googleSignInTap != null)
                        _GoogleSignInButton(onPressed: googleSignInTap)
                      else
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Google account connected',
                                style:
                                    TextStyle(color: _kTextMuted, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(
              color: _kCardSoft,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: _CloudBackupSummary(
              backupEnabled: backupEnabled,
              backedUpCount: backedUpCount,
              backedUpItemNames: backedUpItemNames,
              isUsageLoading: isUsageLoading,
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudBackupSummary extends StatelessWidget {
  const _CloudBackupSummary({
    required this.backupEnabled,
    required this.backedUpCount,
    required this.backedUpItemNames,
    required this.isUsageLoading,
  });

  final bool backupEnabled;
  final int backedUpCount;
  final List<String> backedUpItemNames;
  final bool isUsageLoading;

  @override
  Widget build(BuildContext context) {
    final usageProgress = cloudBackupUsageProgress(
      backedUpCount: backedUpCount,
    );
    final progressColor = backedUpCount >= cloudBackupWarningThreshold
        ? AppColors.warning
        : _kAccent;
    final previewNames = backedUpItemNames.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.cloud_done,
              color: backupEnabled ? _kAccent : AppColors.error,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cloudBackupUsageLabel(
                  backedUpCount: backedUpCount,
                ),
                style: TextStyle(
                  color: _kTextPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: isUsageLoading ? null : usageProgress,
          minHeight: 9,
          backgroundColor: _kBorder.withValues(alpha: 0.35),
          valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          borderRadius: BorderRadius.circular(999),
        ),
        const SizedBox(height: 14),
        Text(
          backupEnabled
              ? backedUpCount > 0
                  ? 'These items are already marked for cloud backup. Tap Online Backup below to sync or restore them now.'
                  : 'Cloud backup is ready. Tap Online Backup below whenever you want to sync or restore your saved cloud data.'
              : 'Turn on cloud backup for an item, or use Online Backup below to restore items already saved to your account.',
          style: TextStyle(
            color: _kTextMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        if (previewNames.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Backed up items',
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in previewNames) _CloudItemChip(label: name),
              if (backedUpItemNames.length > previewNames.length)
                _CloudItemChip(
                  label:
                      '+${backedUpItemNames.length - previewNames.length} more',
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CloudItemChip extends StatelessWidget {
  const _CloudItemChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _kTextPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDADCE0), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.white,
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFF4285F4),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Google Sign In',
                    style: TextStyle(
                      color: Color(0xFF1F1F1F),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard({
    required this.darkMode,
    required this.stillThere,
    required this.seasonal,
    required this.lentReminders,
    required this.onDarkModeChanged,
    required this.onStillThereChanged,
    required this.onSeasonalChanged,
    required this.onLentRemindersChanged,
  });

  final bool darkMode;
  final bool stillThere;
  final bool seasonal;
  final bool lentReminders;
  final ValueChanged<bool> onDarkModeChanged;
  final ValueChanged<bool> onStillThereChanged;
  final ValueChanged<bool> onSeasonalChanged;
  final ValueChanged<bool> onLentRemindersChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dark_mode, color: _kIcon, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Dark Mode',
                    style: TextStyle(
                        color: _kTextPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                _IkeepSwitch(value: darkMode, onChanged: onDarkModeChanged),
              ],
            ),
            const SizedBox(height: 18),
            Divider(color: _kBorder, height: 1),
            const SizedBox(height: 18),
            Text(
              'NOTIFICATIONS',
              style: TextStyle(
                color: _kTextMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 14),
            _NotificationRow(
              title: '"Still there?" Reminders',
              subtitle: 'Weekly stale-item spot checks',
              value: stillThere,
              onChanged: onStillThereChanged,
            ),
            const SizedBox(height: 16),
            _NotificationRow(
              title: 'Seasonal Reminders',
              subtitle: 'Background monthly seasonal prompts',
              value: seasonal,
              onChanged: onSeasonalChanged,
            ),
            const SizedBox(height: 16),
            _NotificationRow(
              title: '"I Lent It" Reminders',
              subtitle: 'Due-date morning alerts plus one 48h follow-up',
              value: lentReminders,
              onChanged: onLentRemindersChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: _kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: _kTextMuted, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _IkeepSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _NearbyLendingCard extends ConsumerWidget {
  const _NearbyLendingCard({
    required this.nearbyEnabled,
    this.cachedLocality,
  });

  final bool nearbyEnabled;
  final String? cachedLocality;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.near_me, color: _kIcon, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nearby Discovery',
                        style: TextStyle(
                          color: _kTextPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Let neighbors discover your lendable items',
                        style: TextStyle(
                          color: _kTextMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: _kBorder, height: 1),
            const SizedBox(height: 16),

            // Locality info
            if (cachedLocality != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Locality',
                            style: TextStyle(
                              color: _kTextMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            cachedLocality!,
                            style: TextStyle(
                              color: _kTextPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final locationService =
                            ref.read(locationServiceProvider);
                        final locality =
                            await locationService.refreshLocality();
                        if (locality != null) {
                          ref
                              .read(settingsProvider.notifier)
                              .setCachedLocality(locality);
                        }
                      },
                      icon: const Icon(Icons.refresh,
                          color: AppColors.primary, size: 20),
                      tooltip: 'Refresh locality',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Privacy note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.info, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Only your locality name is shared — never your GPS coordinates. '
                      'Items are visible per-item, not globally. You control each item\'s visibility.',
                      style: TextStyle(
                        color: _kTextMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
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
}

class _CloudAndFamilyCard extends StatelessWidget {
  const _CloudAndFamilyCard({
    required this.statusText,
    required this.statusColor,
    required this.isSyncing,
    required this.progress,
    required this.lastSyncedText,
    required this.onSyncTap,
    required this.onManageFamily,
  });

  final String statusText;
  final Color statusColor;
  final bool isSyncing;
  final double progress;
  final String lastSyncedText;
  final VoidCallback? onSyncTap;
  final VoidCallback onManageFamily;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onSyncTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (isSyncing)
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _kAccent.withValues(alpha: 0.8),
                          ),
                        )
                      else
                        const Icon(Icons.sync, color: _kAccent, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Online Backup',
                          style: TextStyle(
                            color: _kTextPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: isSyncing ? null : progress,
                    minHeight: 8,
                    backgroundColor: _kCardSoft,
                    valueColor: const AlwaysStoppedAnimation<Color>(_kAccent),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.schedule, color: _kTextMuted, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Last Synced: $lastSyncedText',
                        style: TextStyle(color: _kTextMuted, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: _kBorder),
          _ActionRow(
            icon: Icons.groups_rounded,
            title: 'Manage Family',
            trailing: Icons.chevron_right,
            onTap: onManageFamily,
          ),
        ],
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({
    required this.onHelp,
    required this.onContact,
    required this.onTerms,
    required this.onDeleteAccount,
  });

  final VoidCallback onHelp;
  final VoidCallback onContact;
  final VoidCallback onTerms;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          _ActionRow(
            icon: Icons.help_outline,
            title: 'Help Center',
            trailing: Icons.open_in_new,
            onTap: onHelp,
          ),
          Divider(height: 1, color: _kBorder),
          _ActionRow(
            icon: Icons.mail_outline,
            title: 'Contact Us',
            trailing: Icons.chevron_right,
            onTap: onContact,
          ),
          Divider(height: 1, color: _kBorder),
          _ActionRow(
            icon: Icons.description_outlined,
            title: 'Terms & Privacy',
            trailing: Icons.chevron_right,
            onTap: onTerms,
          ),
          Divider(height: 1, color: _kBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onDeleteAccount,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: _kTextMuted,
                ),
                child: const Text(
                  'Account deletion',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final IconData trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Icon(icon, color: _kIcon, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: _kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(trailing, color: _kIcon, size: 29),
          ],
        ),
      ),
    );
  }
}

class _IkeepSwitch extends StatelessWidget {
  const _IkeepSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 62,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: value ? _kAccent : _kSwitchOffTrack,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.white : _kSwitchOffThumb,
            ),
          ),
        ),
      ),
    );
  }
}
