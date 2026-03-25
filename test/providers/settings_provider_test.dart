import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ikeep/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadStoredAppSettings', () {
    test('defaults to light theme for a fresh install', () async {
      SharedPreferences.setMockInitialValues({});

      final settings = await loadStoredAppSettings();

      expect(settings.themeMode, ThemeMode.light);
    });

    test('restores a previously saved dark theme', () async {
      SharedPreferences.setMockInitialValues({
        AppSettingsKeys.themeMode: ThemeMode.dark.index,
        AppSettingsKeys.onboardingComplete: true,
      });

      final settings = await loadStoredAppSettings();

      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.isOnboardingComplete, isTrue);
    });

    test('falls back to light for an invalid stored theme value', () async {
      SharedPreferences.setMockInitialValues({
        AppSettingsKeys.themeMode: 99,
      });

      final settings = await loadStoredAppSettings();

      expect(settings.themeMode, ThemeMode.light);
    });

    test('clears legacy premium preferences during load', () async {
      SharedPreferences.setMockInitialValues({
        'is_premium': true,
        'app_plan': 2,
      });

      await loadStoredAppSettings();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('is_premium'), isFalse);
      expect(prefs.containsKey('app_plan'), isFalse);
    });
  });

  test('setThemeMode updates state and persists the selected mode', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier =
        SettingsNotifier(initialSettings: await loadStoredAppSettings());

    await notifier.setThemeMode(ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(notifier.state.themeMode, ThemeMode.dark);
    expect(prefs.getInt(AppSettingsKeys.themeMode), ThemeMode.dark.index);
  });
}
