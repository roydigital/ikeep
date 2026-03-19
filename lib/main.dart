import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'services/background_scheduler_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  await BackgroundSchedulerService.instance.initialize();
  await BackgroundSchedulerService.instance.syncFromStoredSettings();

  runApp(
    const ProviderScope(
      child: IkeepApp(),
    ),
  );
}
