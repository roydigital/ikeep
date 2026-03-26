enum SyncStatus { idle, syncing, success, error }

class SyncResult {
  const SyncResult({
    required this.status,
    this.errorMessage,
    this.lastSyncedAt,
    this.partialFailure = false,
  });

  const SyncResult.idle()
      : status = SyncStatus.idle,
        errorMessage = null,
        lastSyncedAt = null,
        partialFailure = false;

  const SyncResult.syncing()
      : status = SyncStatus.syncing,
        errorMessage = null,
        lastSyncedAt = null,
        partialFailure = false;

  factory SyncResult.success({bool partialFailure = false}) => SyncResult(
        status: SyncStatus.success,
        lastSyncedAt: DateTime.now(),
        partialFailure: partialFailure,
      );

  const SyncResult.error(String message)
      : status = SyncStatus.error,
        errorMessage = message,
        lastSyncedAt = null,
        partialFailure = false;

  final SyncStatus status;
  final String? errorMessage;
  final DateTime? lastSyncedAt;

  /// True when the sync completed but one or more attachments (images or
  /// invoice) could not be uploaded. The item record itself was saved.
  final bool partialFailure;

  bool get isSyncing => status == SyncStatus.syncing;
  bool get hasError => status == SyncStatus.error;
  bool get isSuccess => status == SyncStatus.success;
}
