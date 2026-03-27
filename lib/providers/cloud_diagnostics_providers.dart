import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/cloud_diagnostics_snapshot.dart';
import 'service_providers.dart';

final cloudDiagnosticsSnapshotProvider =
    FutureProvider.autoDispose<CloudDiagnosticsSnapshot>((ref) async {
  return ref.watch(cloudDiagnosticsServiceProvider).loadSnapshot();
});
