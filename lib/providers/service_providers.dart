import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/appwrite_sync_service.dart';
import '../services/image_service.dart';
import '../services/ml_label_service.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';

final imageServiceProvider = Provider<ImageService>(
  (ref) => ImageService(),
);

final mlLabelServiceProvider = Provider<MlLabelService>(
  (ref) {
    final service = MlLabelService();
    ref.onDispose(service.dispose);
    return service;
  },
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => AppwriteSyncService(),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
