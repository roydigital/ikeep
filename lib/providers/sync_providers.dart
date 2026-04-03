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
    // Suppressed error — reset to idle so the UI never stays stuck on
    // "syncing". Previously this reverted to fallbackStatus which was often
    // .syncing() itself, causing an infinite spinner.
    ref.read(syncStatusProvider.notifier).state = const SyncResult.idle();
    return;
  }

  ref.read(syncStatusProvider.notifier).state = result;
  if (result.status == SyncStatus.success) {
    ref.invalidate(lastSyncedAtProvider);
  }
}
