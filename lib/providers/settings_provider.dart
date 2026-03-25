import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/database_provider.dart';

class AppSettingsKeys {
  const AppSettingsKeys._();

  static const String themeMode = 'theme_mode';
  static const String onboardingComplete = 'onboarding_complete';
  static const String backupEnabled = 'backup_enabled';
  static const String stillThereReminders = 'still_there_reminders';
  static const String expiryReminders = 'expiry_reminders';
  static const String seasonalReminders = 'seasonal_reminders';
  static const String lentReminders = 'lent_reminders';
  static const String nearbyEnabled = 'nearby_enabled';
  static const String cachedLocality = 'cached_locality';
}

const List<String> _legacyPremiumPrefKeys = <String>[
  'is_premium',
  'app_plan',
];

ThemeMode _storedThemeModeFromPrefs(SharedPreferences prefs) {
  final storedIndex = prefs.getInt(AppSettingsKeys.themeMode);
  if (storedIndex != null &&
      storedIndex >= 0 &&
      storedIndex < ThemeMode.values.length) {
    return ThemeMode.values[storedIndex];
  }

  return ThemeMode.light;
}

Future<void> _migrateLegacyPremiumPrefs(SharedPreferences prefs) async {
  for (final key in _legacyPremiumPrefKeys) {
    if (prefs.containsKey(key)) {
      await prefs.remove(key);
    }
  }
}

AppSettings appSettingsFromPrefs(SharedPreferences prefs) {
  return AppSettings(
    themeMode: _storedThemeModeFromPrefs(prefs),
    isOnboardingComplete:
        prefs.getBool(AppSettingsKeys.onboardingComplete) ?? false,
    isBackupEnabled: prefs.getBool(AppSettingsKeys.backupEnabled) ?? false,
    stillThereRemindersEnabled:
        prefs.getBool(AppSettingsKeys.stillThereReminders) ?? true,
    expiryRemindersEnabled:
        prefs.getBool(AppSettingsKeys.expiryReminders) ?? true,
    seasonalRemindersEnabled:
        prefs.getBool(AppSettingsKeys.seasonalReminders) ?? true,
    lentRemindersEnabled: prefs.getBool(AppSettingsKeys.lentReminders) ?? true,
    nearbyEnabled: prefs.getBool(AppSettingsKeys.nearbyEnabled) ?? false,
    cachedLocality: prefs.getString(AppSettingsKeys.cachedLocality),
  );
}

Future<AppSettings> loadStoredAppSettings() async {
  final prefs = await SharedPreferences.getInstance();
  await _migrateLegacyPremiumPrefs(prefs);
  return appSettingsFromPrefs(prefs);
}

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.light,
    this.isOnboardingComplete = false,
    this.isBackupEnabled = false,
    this.stillThereRemindersEnabled = true,
    this.expiryRemindersEnabled = true,
    this.seasonalRemindersEnabled = true,
    this.lentRemindersEnabled = true,
    this.nearbyEnabled = false,
    this.cachedLocality,
  });

  final ThemeMode themeMode;
  final bool isOnboardingComplete;
  final bool isBackupEnabled;
  final bool stillThereRemindersEnabled;
  final bool expiryRemindersEnabled;
  final bool seasonalRemindersEnabled;
  final bool lentRemindersEnabled;
  final bool nearbyEnabled;
  final String? cachedLocality;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? isOnboardingComplete,
    bool? isBackupEnabled,
    bool? stillThereRemindersEnabled,
    bool? expiryRemindersEnabled,
    bool? seasonalRemindersEnabled,
    bool? lentRemindersEnabled,
    bool? nearbyEnabled,
    String? cachedLocality,
    bool clearCachedLocality = false,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      isOnboardingComplete: isOnboardingComplete ?? this.isOnboardingComplete,
      isBackupEnabled: isBackupEnabled ?? this.isBackupEnabled,
      stillThereRemindersEnabled:
          stillThereRemindersEnabled ?? this.stillThereRemindersEnabled,
      expiryRemindersEnabled:
          expiryRemindersEnabled ?? this.expiryRemindersEnabled,
      seasonalRemindersEnabled:
          seasonalRemindersEnabled ?? this.seasonalRemindersEnabled,
      lentRemindersEnabled: lentRemindersEnabled ?? this.lentRemindersEnabled,
      nearbyEnabled: nearbyEnabled ?? this.nearbyEnabled,
      cachedLocality:
          clearCachedLocality ? null : (cachedLocality ?? this.cachedLocality),
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier({AppSettings? initialSettings})
      : super(initialSettings ?? const AppSettings()) {
    if (initialSettings == null) {
      _load();
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyPremiumPrefs(prefs);
    state = appSettingsFromPrefs(prefs);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppSettingsKeys.themeMode, mode.index);
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(isOnboardingComplete: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppSettingsKeys.onboardingComplete, true);
  }

  Future<void> setBackupEnabled(bool enabled) async {
    state = state.copyWith(isBackupEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppSettingsKeys.backupEnabled, enabled);
  }

  Future<void> setStillThereReminders(bool enabled) async {
    state = state.copyWith(stillThereRemindersEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppSettingsKeys.stillThereReminders, enabled);
  }

  Future<void> setExpiryReminders(bool enabled) async {
    state = state.copyWith(expiryRemindersEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppSettingsKeys.expiryReminders, enabled);
  }

  Future<void> setSeasonalReminders(bool enabled) async {
    state = state.copyWith(seasonalRemindersEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppSettingsKeys.seasonalReminders, enabled);
  }

  Future<void> setLentReminders(bool enabled) async {
    state = state.copyWith(lentRemindersEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppSettingsKeys.lentReminders, enabled);
  }

  Future<void> setNearbyEnabled(bool enabled) async {
    state = state.copyWith(nearbyEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppSettingsKeys.nearbyEnabled, enabled);
  }

  Future<void> setCachedLocality(String? locality) async {
    if (locality == null) {
      state = state.copyWith(clearCachedLocality: true);
    } else {
      state = state.copyWith(cachedLocality: locality);
    }
    final prefs = await SharedPreferences.getInstance();
    if (locality != null) {
      await prefs.setString(AppSettingsKeys.cachedLocality, locality);
    } else {
      await prefs.remove(AppSettingsKeys.cachedLocality);
    }
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(),
);

final backedUpItemsCountProvider = FutureProvider<int>((ref) async {
  return ref.watch(itemDaoProvider).countBackedUpItems();
});
