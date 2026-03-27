enum SyncStatus { idle, syncing, success, error, timedOut }

/// Outcome for a single item during [fullSync].
class ItemSyncOutcome {
  const ItemSyncOutcome({
    required this.itemUuid,
    required this.itemName,
    required this.success,
    this.partialFailure = false,
    this.errorMessage,
  });

  final String itemUuid;
  final String itemName;
  final bool success;

  /// True when the Firestore write succeeded but one or more attachments
  /// (images or invoice) could not be uploaded.
  final bool partialFailure;
  final String? errorMessage;
}

class SyncResult {
  const SyncResult({
    required this.status,
    this.errorMessage,
    this.lastSyncedAt,
    this.partialFailure = false,
    this.totalItems = 0,
    this.syncedItems = 0,
    this.failedItems = 0,
    this.itemOutcomes = const [],
  });

  const SyncResult.idle()
      : status = SyncStatus.idle,
        errorMessage = null,
        lastSyncedAt = null,
        partialFailure = false,
        totalItems = 0,
        syncedItems = 0,
        failedItems = 0,
        itemOutcomes = const [];

  const SyncResult.syncing()
      : status = SyncStatus.syncing,
        errorMessage = null,
        lastSyncedAt = null,
        partialFailure = false,
        totalItems = 0,
        syncedItems = 0,
        failedItems = 0,
        itemOutcomes = const [];

  factory SyncResult.success({
    bool partialFailure = false,
    int totalItems = 0,
    int syncedItems = 0,
    int failedItems = 0,
    List<ItemSyncOutcome> itemOutcomes = const [],
  }) =>
      SyncResult(
        status: SyncStatus.success,
        lastSyncedAt: DateTime.now(),
        partialFailure: partialFailure,
        totalItems: totalItems,
        syncedItems: syncedItems,
        failedItems: failedItems,
        itemOutcomes: itemOutcomes,
      );

  const SyncResult.error(String message)
      : status = SyncStatus.error,
        errorMessage = message,
        lastSyncedAt = null,
        partialFailure = false,
        totalItems = 0,
        syncedItems = 0,
        failedItems = 0,
        itemOutcomes = const [];

  factory SyncResult.timedOut({
    String? message,
    int totalItems = 0,
    int syncedItems = 0,
    int failedItems = 0,
    List<ItemSyncOutcome> itemOutcomes = const [],
  }) =>
      SyncResult(
        status: SyncStatus.timedOut,
        errorMessage: message ?? 'Sync timed out',
        lastSyncedAt: DateTime.now(),
        totalItems: totalItems,
        syncedItems: syncedItems,
        failedItems: failedItems,
        itemOutcomes: itemOutcomes,
      );

  final SyncStatus status;
  final String? errorMessage;
  final DateTime? lastSyncedAt;

  /// True when the sync completed but one or more attachments (images or
  /// invoice) could not be uploaded. The item record itself was saved.
  final bool partialFailure;

  /// Total items that needed syncing (upload + import + delete).
  final int totalItems;

  /// Items that synced successfully.
  final int syncedItems;

  /// Items that failed to sync.
  final int failedItems;

  /// Per-item outcomes for upload operations.
  final List<ItemSyncOutcome> itemOutcomes;

  bool get isSyncing => status == SyncStatus.syncing;
  bool get hasError =>
      status == SyncStatus.error || status == SyncStatus.timedOut;
  bool get isSuccess => status == SyncStatus.success;
  bool get isTimedOut => status == SyncStatus.timedOut;
}
