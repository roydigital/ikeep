import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sync_status.dart';
import 'service_providers.dart';

final syncStatusProvider = StateProvider<SyncResult>(
  (ref) => const SyncResult.idle(),
);

final lastSyncedAtProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  return ref.watch(syncServiceProvider).getLastSyncedAt();
});

void publishSyncResult(
  Ref ref,
  SyncResult result, {
  bool publishErrors = false,
  SyncResult? fallbackStatus,
}) {
  if (result.status == SyncStatus.error && !publishErrors) {
    if (fallbackStatus != null) {
      ref.read(syncStatusProvider.notifier).state = fallbackStatus;
    }
    return;
  }

  ref.read(syncStatusProvider.notifier).state = result;
  if (result.status == SyncStatus.success) {
    ref.invalidate(lastSyncedAtProvider);
  }
}
