import '../domain/models/item.dart';
import '../domain/models/location_model.dart';
import '../domain/models/sync_status.dart';

/// Abstract interface for cloud sync operations.
/// The concrete Appwrite implementation is swappable here.
abstract class SyncService {
  Future<SyncResult> syncItem(Item item);
  Future<SyncResult> syncLocation(LocationModel location);
  Future<SyncResult> deleteRemoteItem(String uuid);
  Future<SyncResult> deleteRemoteLocation(String uuid);

  /// Performs a full bidirectional sync (pull remote → push local changes).
  Future<SyncResult> fullSync();

  Future<DateTime?> getLastSyncedAt();
}
