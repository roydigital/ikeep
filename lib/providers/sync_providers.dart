import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sync_status.dart';
import 'service_providers.dart';

final syncStatusProvider = StateProvider<SyncResult>(
  (ref) => const SyncResult.idle(),
);

final lastSyncedAtProvider = FutureProvider<DateTime?>((ref) async {
  return ref.watch(syncServiceProvider).getLastSyncedAt();
});
