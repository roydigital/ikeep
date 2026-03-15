import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.isOnboardingComplete = false,
    this.isBackupEnabled = false,
    this.stillThereRemindersEnabled = true,
    this.expiryRemindersEnabled = true,
  });

  final ThemeMode themeMode;
  final bool isOnboardingComplete;
  final bool isBackupEnabled;
  final bool stillThereRemindersEnabled;
  final bool expiryRemindersEnabled;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? isOnboardingComplete,
    bool? isBackupEnabled,
    bool? stillThereRemindersEnabled,
    bool? expiryRemindersEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      isOnboardingComplete: isOnboardingComplete ?? this.isOnboardingComplete,
      isBackupEnabled: isBackupEnabled ?? this.isBackupEnabled,
      stillThereRemindersEnabled:
          stillThereRemindersEnabled ?? this.stillThereRemindersEnabled,
      expiryRemindersEnabled:
          expiryRemindersEnabled ?? this.expiryRemindersEnabled,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  static const _keyThemeMode = 'theme_mode';
  static const _keyOnboarding = 'onboarding_complete';
  static const _keyBackup = 'backup_enabled';
  static const _keyStillThere = 'still_there_reminders';
  static const _keyExpiry = 'expiry_reminders';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt(_keyThemeMode) ?? ThemeMode.dark.index;
    state = AppSettings(
      themeMode: ThemeMode.values[themeModeIndex],
      isOnboardingComplete: prefs.getBool(_keyOnboarding) ?? false,
      isBackupEnabled: prefs.getBool(_keyBackup) ?? false,
      stillThereRemindersEnabled: prefs.getBool(_keyStillThere) ?? true,
      expiryRemindersEnabled: prefs.getBool(_keyExpiry) ?? true,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, mode.index);
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(isOnboardingComplete: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboarding, true);
  }

  Future<void> setBackupEnabled(bool enabled) async {
    state = state.copyWith(isBackupEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackup, enabled);
  }

  Future<void> setStillThereReminders(bool enabled) async {
    state = state.copyWith(stillThereRemindersEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStillThere, enabled);
  }

  Future<void> setExpiryReminders(bool enabled) async {
    state = state.copyWith(expiryRemindersEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyExpiry, enabled);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(),
);
