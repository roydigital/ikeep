import '../domain/models/item.dart';
import '../domain/models/location_model.dart';
import '../domain/models/sync_status.dart';

/// Abstract interface for cloud sync operations.
/// The concrete Appwrite implementation is swappable here.
abstract class SyncService {
  Future<SyncResult> syncItem(Item item);
  Future<SyncResult> syncLocation(LocationModel location);
  Future<SyncResult> deleteRemoteItem(
    String uuid, {
    String reason = 'deleted',
  });
  Future<SyncResult> deleteRemoteLocation(String uuid);

  /// Performs the default personal-backup sync path.
  ///
  /// Phase 5A makes this delta-first with safe fallback to [fullSync()] when
  /// checkpoints are missing, stale, or otherwise unsafe.
  Future<SyncResult> syncAll();

  /// Performs a full bidirectional sync (pull remote → push local changes).
  Future<SyncResult> fullSync();

  Future<DateTime?> getLastSyncedAt();

  /// Returns true if the signed-in user has at least one backed-up item in
  /// the remote store. Used on fresh installs to decide whether to auto-restore.
  /// Returns false if the user is not signed in or the check fails.
  Future<bool> hasRemoteBackup();
}
