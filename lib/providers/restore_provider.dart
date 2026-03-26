import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sync_status.dart';
import '../providers/auth_providers.dart';
import '../providers/database_provider.dart';
import '../providers/service_providers.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_providers.dart';

/// Represents the lifecycle of an automatic cloud restore attempt.
enum AutoRestoreStatus {
  /// No restore has been attempted yet (normal app launch with local data).
  idle,

  /// The app is checking whether the signed-in user has remote backup data.
  detecting,

  /// Remote backup was found and the restore is now running.
  restoring,

  /// The restore completed successfully.
  complete,

  /// The restore failed. [AutoRestoreState.errorMessage] has details.
  error,

  /// The user is not signed in, or the local DB already has data.
  /// No restore is needed.
  notNeeded,
}

class AutoRestoreState {
  const AutoRestoreState({
    this.status = AutoRestoreStatus.idle,
    this.errorMessage,
  });

  final AutoRestoreStatus status;

  /// Set when [status] is [AutoRestoreStatus.error].
  final String? errorMessage;

  bool get isRestoring => status == AutoRestoreStatus.restoring;
  bool get isDetecting => status == AutoRestoreStatus.detecting;
  bool get needsUserAttention =>
      status == AutoRestoreStatus.complete ||
      status == AutoRestoreStatus.error;

  AutoRestoreState copyWith({
    AutoRestoreStatus? status,
    String? errorMessage,
  }) {
    return AutoRestoreState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Notifier that drives the automatic cloud-restore flow on a fresh install.
///
/// On a fresh install the local SQLite database is empty and SharedPreferences
/// has no backup state. After the user signs in the app cannot rely on
/// SharedPreferences to know whether a backup exists. This notifier fills that
/// gap:
///
/// 1. Detects whether the signed-in user has items in Firestore.
/// 2. If yes, runs a full sync to restore items and their attachments.
/// 3. After restore, reconciles [AppSettings.isBackupEnabled] so the UI
///    reflects the correct state.
///
/// External code triggers the flow by calling [checkAndRestore]. Typically
/// this is called once from [app.dart] when auth state changes from
/// signed-out to signed-in.
class AutoRestoreNotifier extends StateNotifier<AutoRestoreState> {
  AutoRestoreNotifier(this._ref) : super(const AutoRestoreState());

  final Ref _ref;

  /// Checks for remote backup and restores if needed.
  ///
  /// Safe to call multiple times — re-entrant calls while a restore is
  /// already in progress are ignored.
  Future<void> checkAndRestore() async {
    // Do not start a second restore while one is running.
    if (state.status == AutoRestoreStatus.detecting ||
        state.status == AutoRestoreStatus.restoring) {
      return;
    }

    final user = _ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      state = const AutoRestoreState(status: AutoRestoreStatus.notNeeded);
      return;
    }

    // If the local database already has items this is not a fresh install —
    // no automatic restore is needed.
    try {
      final localItems = await _ref.read(itemDaoProvider).getAllItems();
      if (localItems.isNotEmpty) {
        state = const AutoRestoreState(status: AutoRestoreStatus.notNeeded);
        return;
      }
    } catch (e) {
      debugPrint('AutoRestoreNotifier: failed to read local items: $e');
      state = AutoRestoreState(
        status: AutoRestoreStatus.error,
        errorMessage: 'Could not read local database: $e',
      );
      return;
    }

    // ── Detect whether remote backup exists ──────────────────────────────────
    state = const AutoRestoreState(status: AutoRestoreStatus.detecting);

    bool hasBackup;
    try {
      hasBackup = await _ref.read(syncServiceProvider).hasRemoteBackup();
    } catch (e) {
      debugPrint('AutoRestoreNotifier: backup detection failed: $e');
      state = AutoRestoreState(
        status: AutoRestoreStatus.error,
        errorMessage: 'Could not check for cloud backup: $e',
      );
      return;
    }

    if (!hasBackup) {
      state = const AutoRestoreState(status: AutoRestoreStatus.notNeeded);
      return;
    }

    // ── Run the restore ───────────────────────────────────────────────────────
    state = const AutoRestoreState(status: AutoRestoreStatus.restoring);
    _ref.read(syncStatusProvider.notifier).state = const SyncResult.syncing();

    SyncResult result;
    try {
      result = await _ref.read(syncServiceProvider).fullSync();
    } catch (e) {
      debugPrint('AutoRestoreNotifier: fullSync threw: $e');
      result = SyncResult.error(e.toString());
    }

    _ref.read(syncStatusProvider.notifier).state = result;
    _ref.invalidate(lastSyncedAtProvider);

    if (result.isSuccess) {
      // Reconcile backup_enabled: the user clearly has backed-up items, so
      // reflect that in settings even though SharedPreferences was wiped.
      try {
        final backedUpCount =
            await _ref.read(itemDaoProvider).countBackedUpItems();
        if (backedUpCount > 0) {
          await _ref.read(settingsProvider.notifier).setBackupEnabled(true);
        }
      } catch (e) {
        debugPrint(
          'AutoRestoreNotifier: settings reconciliation failed: $e',
        );
      }

      state = const AutoRestoreState(status: AutoRestoreStatus.complete);
      debugPrint('AutoRestoreNotifier: restore complete');
    } else {
      state = AutoRestoreState(
        status: AutoRestoreStatus.error,
        errorMessage: result.errorMessage ?? 'Restore failed',
      );
      debugPrint(
        'AutoRestoreNotifier: restore failed — ${result.errorMessage}',
      );
    }
  }

  /// Resets the notifier to [idle] so a future sign-in can trigger the flow
  /// again (e.g. after a sign-out followed by a sign-in with a different
  /// account).
  void reset() {
    state = const AutoRestoreState();
  }
}

final autoRestoreProvider =
    StateNotifierProvider<AutoRestoreNotifier, AutoRestoreState>(
  (ref) => AutoRestoreNotifier(ref),
);
