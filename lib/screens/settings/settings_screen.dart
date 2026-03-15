import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models/sync_status.dart';
import '../../providers/item_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_providers.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_nav_bar.dart';

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
    required this.accountSwitchBg,
    required this.accountSwitchFg,
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
  final Color accountSwitchBg;
  final Color accountSwitchFg;
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
  accountSwitchBg: AppColors.surfaceVariantDark,
  accountSwitchFg: AppColors.primary,
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
  accountSwitchBg: AppColors.surfaceVariantLight,
  accountSwitchFg: AppColors.primary,
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
Color get _kAccountSwitchBg => _activeColors.accountSwitchBg;
Color get _kAccountSwitchFg => _activeColors.accountSwitchFg;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _initialized = false;
  bool _darkMode = true;
  bool _stillThere = true;
  bool _seasonal = true;
  bool _backupEnabled = false;
  bool _isSaving = false;

  void _initFromSettings(AppSettings settings) {
    if (_initialized) return;
    _darkMode = settings.themeMode == ThemeMode.dark;
    _stillThere = settings.stillThereRemindersEnabled;
    _seasonal = settings.expiryRemindersEnabled;
    _backupEnabled = settings.isBackupEnabled;
    _initialized = true;
  }

  bool _hasChanges(AppSettings settings) {
    return _darkMode != (settings.themeMode == ThemeMode.dark) ||
        _stillThere != settings.stillThereRemindersEnabled ||
        _seasonal != settings.expiryRemindersEnabled ||
        _backupEnabled != settings.isBackupEnabled;
  }

  Future<void> _save(AppSettings settings) async {
    if (_isSaving || !_hasChanges(settings)) return;
    setState(() => _isSaving = true);
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.setThemeMode(_darkMode ? ThemeMode.dark : ThemeMode.light);
    await notifier.setStillThereReminders(_stillThere);
    await notifier.setExpiryReminders(_seasonal);
    await notifier.setBackupEnabled(_backupEnabled);
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<void> _runSync() async {
    ref.read(syncStatusProvider.notifier).state = const SyncResult.syncing();
    final result = await ref.read(syncServiceProvider).fullSync();
    ref.read(syncStatusProvider.notifier).state = result;
    ref.invalidate(lastSyncedAtProvider);
    if (!mounted) return;
    final message = result.isSuccess
        ? 'Sync completed'
        : (result.errorMessage ?? 'Sync failed');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportData() async {
    final colors = _darkMode ? _darkColors : _lightColors;
    try {
      final items = await ref.read(allItemsProvider.future);
      final locations = await ref.read(allLocationsProvider.future);
      final payload = {
        'exportedAt': DateTime.now().toIso8601String(),
        'itemsCount': items.length,
        'locationsCount': locations.length,
        'items': items.map((e) => e.toJson()).toList(),
        'locations': locations.map((e) => e.toJson()).toList(),
      };
      final json = const JsonEncoder.withIndent('  ').convert(payload);
      await Clipboard.setData(ClipboardData(text: json));
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
            'Copied ${items.length} items and ${locations.length} locations to clipboard as JSON.',
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

  void _showInfo(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    final syncStatus = ref.watch(syncStatusProvider);
    final lastSynced = ref.watch(lastSyncedAtProvider).valueOrNull;
    _initFromSettings(settings);
    _activeColors = _darkMode ? _darkColors : _lightColors;

    final canSave = _hasChanges(settings) && !_isSaving;
    final statusColor = syncStatus.hasError ? AppColors.error : _kSuccess;
    final statusText = syncStatus.isSyncing
        ? 'Syncing...'
        : syncStatus.hasError
            ? 'Error'
            : 'Connected';
    final bottomInset = MediaQuery.of(context).padding.bottom;

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
                  padding: EdgeInsets.fromLTRB(20, 24, 20, bottomInset + 110),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        _SectionLabel('ACCOUNT'),
                        const SizedBox(height: 14),
                        _AccountCard(
                          backupEnabled: _backupEnabled,
                          onSwitch: () {
                            setState(() => _backupEnabled = !_backupEnabled);
                          },
                        ),
                        const SizedBox(height: 36),
                        _SectionLabel('PREFERENCES'),
                        const SizedBox(height: 14),
                        _PreferencesCard(
                          darkMode: _darkMode,
                          stillThere: _stillThere,
                          seasonal: _seasonal,
                          onDarkModeChanged: (v) =>
                              setState(() => _darkMode = v),
                          onStillThereChanged: (v) =>
                              setState(() => _stillThere = v),
                          onSeasonalChanged: (v) =>
                              setState(() => _seasonal = v),
                        ),
                        const SizedBox(height: 36),
                        _SectionLabel('DATA & BACKUP'),
                        const SizedBox(height: 14),
                        _DataBackupCard(
                          statusText: statusText,
                          statusColor: statusColor,
                          isSyncing: syncStatus.isSyncing,
                          progress: _backupEnabled ? 0.85 : 0.25,
                          lastSyncedText: _formatLastSynced(lastSynced),
                          onSyncTap: _runSync,
                          onExportTap: _exportData,
                        ),
                        const SizedBox(height: 36),
                        _SectionLabel('SUPPORT'),
                        const SizedBox(height: 14),
                        _SupportCard(
                          onHelp: () => _showInfo('Help Center coming soon'),
                          onContact: () =>
                              _showInfo('Contact: support@ikeep.app'),
                          onTerms: () =>
                              _showInfo('Terms & Privacy coming soon'),
                        ),
                        const SizedBox(height: 52),
                        Center(
                          child: Text(
                            'Ikeep Version 2.4.0 (b892)',
                            style: TextStyle(
                              color: _kTextMuted,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: TextButton(
                            onPressed: () => _showInfo('Logged out'),
                            child: const Text(
                              'Log Out',
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 33 / 2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AppNavBar(activeTab: AppNavTab.settings),
          ),
        ],
      ),
    );
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
              fontSize: 19,
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
                      fontSize: 16.5,
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
        fontSize: 17,
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.backupEnabled,
    required this.onSwitch,
  });

  final bool backupEnabled;
  final VoidCallback onSwitch;

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
                  child: const Icon(Icons.person,
                      color: Color(0xFF9A8E76), size: 42),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alex Johnson',
                        style: TextStyle(
                          color: _kTextPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: AppColors.success, size: 18),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Signed in with Google',
                              style:
                                  TextStyle(color: _kTextMuted, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccountSwitchBg,
                    foregroundColor: _kAccountSwitchFg,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 11),
                  ),
                  onPressed: onSwitch,
                  child: const Text(
                    'Switch',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5),
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
            child: Row(
              children: [
                const Icon(Icons.cloud_done, color: _kAccent, size: 24),
                const SizedBox(width: 10),
                Text(
                  backupEnabled
                      ? 'Backup & Sync Active'
                      : 'Backup & Sync Inactive',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                Text(
                  backupEnabled ? 'Premium Member' : 'Free Member',
                  style: TextStyle(color: _kTextMuted, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard({
    required this.darkMode,
    required this.stillThere,
    required this.seasonal,
    required this.onDarkModeChanged,
    required this.onStillThereChanged,
    required this.onSeasonalChanged,
  });

  final bool darkMode;
  final bool stillThere;
  final bool seasonal;
  final ValueChanged<bool> onDarkModeChanged;
  final ValueChanged<bool> onStillThereChanged;
  final ValueChanged<bool> onSeasonalChanged;

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
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 14),
            _NotificationRow(
              title: '"Still there?" Reminders',
              subtitle: 'Periodic checks for inactive items',
              value: stillThere,
              onChanged: onStillThereChanged,
            ),
            const SizedBox(height: 16),
            _NotificationRow(
              title: 'Seasonal Reminders',
              subtitle: 'Suggestions based on the time of year',
              value: seasonal,
              onChanged: onSeasonalChanged,
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
                style: TextStyle(color: _kTextMuted, fontSize: 16.5),
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

class _DataBackupCard extends StatelessWidget {
  const _DataBackupCard({
    required this.statusText,
    required this.statusColor,
    required this.isSyncing,
    required this.progress,
    required this.lastSyncedText,
    required this.onSyncTap,
    required this.onExportTap,
  });

  final String statusText;
  final Color statusColor;
  final bool isSyncing;
  final double progress;
  final String lastSyncedText;
  final VoidCallback onSyncTap;
  final VoidCallback onExportTap;

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
                      const Icon(Icons.sync, color: _kAccent, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Appwrite Sync Status',
                          style: TextStyle(
                            color: _kTextPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 19,
                          ),
                        ),
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16.5,
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
                        style: TextStyle(color: _kTextMuted, fontSize: 15),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: _kBorder),
          _ActionRow(
            icon: Icons.download,
            title: 'Export Data',
            trailing: Icons.chevron_right,
            onTap: onExportTap,
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
  });

  final VoidCallback onHelp;
  final VoidCallback onContact;
  final VoidCallback onTerms;

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
                  fontSize: 19,
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

