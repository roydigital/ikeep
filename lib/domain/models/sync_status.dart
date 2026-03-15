enum SyncStatus { idle, syncing, success, error }

class SyncResult {
  const SyncResult({
    required this.status,
    this.errorMessage,
    this.lastSyncedAt,
  });

  const SyncResult.idle()
      : status = SyncStatus.idle,
        errorMessage = null,
        lastSyncedAt = null;

  const SyncResult.syncing()
      : status = SyncStatus.syncing,
        errorMessage = null,
        lastSyncedAt = null;

  factory SyncResult.success() => SyncResult(
        status: SyncStatus.success,
        lastSyncedAt: DateTime.now(),
      );

  const SyncResult.error(String message)
      : status = SyncStatus.error,
        errorMessage = message,
        lastSyncedAt = null;

  final SyncStatus status;
  final String? errorMessage;
  final DateTime? lastSyncedAt;

  bool get isSyncing => status == SyncStatus.syncing;
  bool get hasError => status == SyncStatus.error;
  bool get isSuccess => status == SyncStatus.success;
}
