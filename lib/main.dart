import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'providers/settings_provider.dart';
import 'services/background_scheduler_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  await BackgroundSchedulerService.instance.initialize();
  await BackgroundSchedulerService.instance.syncFromStoredSettings();
  final initialSettings = await loadStoredAppSettings();

  runApp(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsNotifier(initialSettings: initialSettings),
        ),
      ],
      child: const IkeepApp(),
    ),
  );
}
