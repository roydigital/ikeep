import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'app.dart';
import 'providers/firebase_status_provider.dart';
import 'providers/settings_provider.dart';
import 'services/background_scheduler_service.dart';

Future<void> main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    bool firebaseReady = false;
    try {
      await Firebase.initializeApp();
      firebaseReady = true;
    } catch (e, st) {
      debugPrint('Firebase init failed: $e');
      debugPrint('Stack: $st');
      // Cannot use Crashlytics here since Firebase itself failed.
      // App will run in local-only degraded mode.
    }

    if (firebaseReady) {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);

      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;

      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } else {
      debugPrint(
          '⚠️ Ikeep running in local-only mode — cloud features unavailable');
    }

    await BackgroundSchedulerService.instance.initialize();
    await BackgroundSchedulerService.instance.syncFromStoredSettings();
    final initialSettings = await loadStoredAppSettings();

    runApp(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWith((ref) => firebaseReady),
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(initialSettings: initialSettings),
          ),
        ],
        child: const IkeepApp(),
      ),
    );
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}
