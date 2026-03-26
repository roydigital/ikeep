import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sync_status.dart';
import 'auth_providers.dart';
import 'database_provider.dart';
import 'item_providers.dart';
import 'location_providers.dart';
import 'service_providers.dart';
import 'settings_provider.dart';
import 'sync_providers.dart';

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
      status == AutoRestoreStatus.complete || status == AutoRestoreStatus.error;

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
/// The same notifier also exposes [syncAfterSignIn] for the interactive Google
/// sign-in flow in Settings so that a successful sign-in behaves like an
/// immediate Online Backup tap.
class AutoRestoreNotifier extends StateNotifier<AutoRestoreState> {
  AutoRestoreNotifier(this._ref) : super(const AutoRestoreState());

  final Ref _ref;

  bool get _isSyncInProgress =>
      state.status == AutoRestoreStatus.detecting ||
      state.status == AutoRestoreStatus.restoring;

  User? get _currentUser =>
      _ref.read(firebaseAuthProvider).currentUser ??
      _ref.read(authStateProvider).valueOrNull;

  /// Runs a full sync immediately after an interactive Google sign-in.
  ///
  /// This mirrors the manual Online Backup action so the user's cloud items
  /// become visible as soon as sign-in completes.
  Future<SyncResult> syncAfterSignIn() async {
    if (_isSyncInProgress) {
      return const SyncResult.syncing();
    }

    final user = _currentUser;
    if (user == null) {
      state = const AutoRestoreState(status: AutoRestoreStatus.notNeeded);
      return const SyncResult.error(
        'Please sign in with Google before syncing',
      );
    }

    state = const AutoRestoreState(status: AutoRestoreStatus.restoring);
    return _runFullSync();
  }

  /// Checks for remote backup and restores if needed.
  ///
  /// Safe to call multiple times; re-entrant calls while a restore is already
  /// in progress are ignored.
  Future<void> checkAndRestore() async {
    if (_isSyncInProgress) {
      return;
    }

    final user = _currentUser;
    if (user == null) {
      state = const AutoRestoreState(status: AutoRestoreStatus.notNeeded);
      return;
    }

    // If the local database already has items this is not a fresh install,
    // so the app should not auto-restore on startup.
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

    state = const AutoRestoreState(status: AutoRestoreStatus.restoring);
    await _runFullSync();
  }

  /// Resets the notifier to [idle] so a future sign-in can trigger the flow
  /// again (e.g. after a sign-out followed by a sign-in with a different
  /// account).
  void reset() {
    state = const AutoRestoreState();
  }

  Future<SyncResult> _runFullSync() async {
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
      await _reconcileBackupSettings();
      _invalidateSyncedDataProviders();
      state = const AutoRestoreState(status: AutoRestoreStatus.complete);
      debugPrint('AutoRestoreNotifier: restore complete');
      return result;
    }

    state = AutoRestoreState(
      status: AutoRestoreStatus.error,
      errorMessage: result.errorMessage ?? 'Restore failed',
    );
    debugPrint(
      'AutoRestoreNotifier: restore failed - ${result.errorMessage}',
    );
    return result;
  }

  Future<void> _reconcileBackupSettings() async {
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
  }

  void _invalidateSyncedDataProviders() {
    _ref.invalidate(allItemsProvider);
    _ref.invalidate(backedUpItemsProvider);
    _ref.invalidate(archivedItemsProvider);
    _ref.invalidate(lentItemsProvider);
    _ref.invalidate(expiringSoonItemsProvider);
    _ref.invalidate(warrantyEndingSoonItemsProvider);
    _ref.invalidate(lendableItemsProvider);
    _ref.invalidate(forgottenItemsProvider);
    _ref.invalidate(itemTagsProvider);
    _ref.invalidate(searchResultsProvider);
    _ref.invalidate(allLocationsProvider);
    _ref.invalidate(rootLocationsProvider);
    _ref.invalidate(backedUpItemsCountProvider);
  }
}

final autoRestoreProvider =
    StateNotifierProvider<AutoRestoreNotifier, AutoRestoreState>(
  (ref) => AutoRestoreNotifier(ref),
);
