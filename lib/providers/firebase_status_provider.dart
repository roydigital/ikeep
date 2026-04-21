import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether Firebase initialized successfully at app startup.
///
/// When `false`, the app is running in local-only degraded mode: cloud
/// features (sync, backup, household sharing, Crashlytics) are unavailable
/// but local SQLite-backed flows continue to work.
///
/// The real value is injected from `main.dart` via `ProviderScope` overrides
/// after the `Firebase.initializeApp()` call resolves.
final firebaseReadyProvider = StateProvider<bool>((ref) => false);
