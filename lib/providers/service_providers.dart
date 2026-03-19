import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';

import 'database_provider.dart';
import '../services/background_scheduler_service.dart';
import '../services/firebase_image_upload_service.dart';
import '../services/firebase_sync_service.dart';
import '../services/household_cloud_service.dart';
import '../services/household_sync_service.dart';
import '../services/image_optimizer_service.dart';
import '../services/image_service.dart';
import '../services/location_service.dart';
import '../services/ml_label_service.dart';
import '../services/nearby_cloud_service.dart';
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

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final firebaseFirestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

final imageOptimizerServiceProvider = Provider<ImageOptimizerService>(
  (ref) => ImageOptimizerService(),
);

final firebaseImageUploadServiceProvider = Provider<FirebaseImageUploadService>(
  (ref) => FirebaseImageUploadService(
    storage: ref.watch(firebaseStorageProvider),
    optimizer: ref.watch(imageOptimizerServiceProvider),
  ),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => FirebaseSyncService(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
    itemDao: ref.watch(itemDaoProvider),
    locationDao: ref.watch(locationDaoProvider),
    imageUploadService: ref.watch(firebaseImageUploadServiceProvider),
  ),
);

final householdCloudServiceProvider = Provider<HouseholdCloudService>(
  (ref) => HouseholdCloudService(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
    imageUploadService: ref.watch(firebaseImageUploadServiceProvider),
  ),
);

final householdSyncServiceProvider = Provider<HouseholdSyncService>(
  (ref) {
    final service = HouseholdSyncService(
      auth: ref.watch(firebaseAuthProvider),
      firestore: ref.watch(firebaseFirestoreProvider),
      itemDao: ref.watch(itemDaoProvider),
      historyDao: ref.watch(historyDaoProvider),
      pendingSyncDao: ref.watch(pendingSyncDaoProvider),
      householdCloudService: ref.watch(householdCloudServiceProvider),
    );
    ref.onDispose(() {
      unawaited(service.dispose());
    });
    return service;
  },
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final backgroundSchedulerServiceProvider = Provider<BackgroundSchedulerService>(
  (ref) => BackgroundSchedulerService.instance,
);

final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);

final nearbyCloudServiceProvider = Provider<NearbyCloudService>(
  (ref) => NearbyCloudService(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
  ),
);
