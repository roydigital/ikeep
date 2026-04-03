import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';

import 'database_provider.dart';
import '../services/background_scheduler_service.dart';
import '../services/app_info_service.dart';
import '../services/cloud_diagnostics_service.dart';
import '../services/cloud_observation_service.dart';
import '../services/cloud_quota_service.dart';
import '../services/firebase_invoice_storage_service.dart';
import '../services/location_hierarchy_migration_service.dart';
import '../services/firebase_image_upload_service.dart';
import '../services/firebase_sync_service.dart';
import '../services/household_cloud_service.dart';
import '../services/household_sync_service.dart';
import '../services/image_optimizer_service.dart';
import '../services/image_service.dart';
import '../services/invoice_service.dart';
import '../services/media_cache_service.dart';
import '../services/item_cloud_media_service.dart';
import '../services/pdf_optimizer_service.dart';
import '../services/location_service.dart';
import '../services/ml_label_service.dart';
import '../services/nearby_cloud_service.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../domain/models/cloud_entitlement.dart';

final imageServiceProvider = Provider<ImageService>(
  (ref) => ImageService(),
);

final appInfoServiceProvider = Provider<AppInfoService>(
  (ref) => AppInfoService(),
);

final appStoreVersionLabelProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.watch(appInfoServiceProvider).getStoreVersionLabel(),
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

final cloudEntitlementModeProvider = Provider<CloudEntitlementMode>(
  (ref) => CloudEntitlementMode.closedTestingFreeAccess,
);

final cloudObservationServiceProvider = Provider<CloudObservationService>(
  (ref) => CloudObservationService(
    observationDao: ref.watch(cloudObservationDaoProvider),
    planMode: ref.watch(cloudEntitlementModeProvider),
  ),
);

final mediaCacheServiceProvider = Provider<MediaCacheService>(
  (ref) => MediaCacheService(
    storage: ref.watch(firebaseStorageProvider),
    mediaCacheDao: ref.watch(mediaCacheDaoProvider),
    cloudObservationService: ref.watch(cloudObservationServiceProvider),
  ),
);

final itemCloudMediaServiceProvider = Provider<ItemCloudMediaService>(
  (ref) => ItemCloudMediaService(
    storage: ref.watch(firebaseStorageProvider),
    itemCloudMediaDao: ref.watch(itemCloudMediaDaoProvider),
    mediaCacheService: ref.watch(mediaCacheServiceProvider),
  ),
);

final cloudQuotaServiceProvider = Provider<CloudQuotaService>(
  (ref) => CloudQuotaService(
    itemDao: ref.watch(itemDaoProvider),
    itemCloudMediaDao: ref.watch(itemCloudMediaDaoProvider),
    householdMemberDao: ref.watch(householdMemberDaoProvider),
    snapshotDao: ref.watch(cloudUsageSnapshotDaoProvider),
    planMode: ref.watch(cloudEntitlementModeProvider),
  ),
);

final cloudDiagnosticsServiceProvider = Provider<CloudDiagnosticsService>(
  (ref) => CloudDiagnosticsService(
    appInfoService: ref.watch(appInfoServiceProvider),
    planMode: ref.watch(cloudEntitlementModeProvider),
    cloudQuotaService: ref.watch(cloudQuotaServiceProvider),
    cloudObservationService: ref.watch(cloudObservationServiceProvider),
    usageSnapshotDao: ref.watch(cloudUsageSnapshotDaoProvider),
    syncCheckpointDao: ref.watch(syncCheckpointDaoProvider),
    pendingSyncDao: ref.watch(pendingSyncDaoProvider),
    mediaCacheService: ref.watch(mediaCacheServiceProvider),
    itemDao: ref.watch(itemDaoProvider),
    householdMemberDao: ref.watch(householdMemberDaoProvider),
  ),
);

final invoiceServiceProvider = Provider<InvoiceService>(
  (ref) => InvoiceService(
    itemCloudMediaService: ref.watch(itemCloudMediaServiceProvider),
  ),
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

final pdfOptimizerServiceProvider = Provider<PdfOptimizerService>(
  (ref) => PdfOptimizerService(),
);

final firebaseInvoiceStorageServiceProvider =
    Provider<FirebaseInvoiceStorageService>(
  (ref) => FirebaseInvoiceStorageService(
    storage: ref.watch(firebaseStorageProvider),
    pdfOptimizer: ref.watch(pdfOptimizerServiceProvider),
  ),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => FirebaseSyncService(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
    itemDao: ref.watch(itemDaoProvider),
    locationDao: ref.watch(locationDaoProvider),
    historyDao: ref.watch(historyDaoProvider),
    syncCheckpointDao: ref.watch(syncCheckpointDaoProvider),
    pendingSyncDao: ref.watch(pendingSyncDaoProvider),
    imageUploadService: ref.watch(firebaseImageUploadServiceProvider),
    invoiceStorageService: ref.watch(firebaseInvoiceStorageServiceProvider),
    itemCloudMediaService: ref.watch(itemCloudMediaServiceProvider),
    cloudQuotaService: ref.watch(cloudQuotaServiceProvider),
    cloudObservationService: ref.watch(cloudObservationServiceProvider),
  ),
);

final householdCloudServiceProvider = Provider<HouseholdCloudService>(
  (ref) => HouseholdCloudService(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
    imageUploadService: ref.watch(firebaseImageUploadServiceProvider),
    invoiceStorageService: ref.watch(firebaseInvoiceStorageServiceProvider),
    cloudQuotaService: ref.watch(cloudQuotaServiceProvider),
    cloudObservationService: ref.watch(cloudObservationServiceProvider),
  ),
);

final householdSyncServiceProvider = Provider<HouseholdSyncService>(
  (ref) {
    final service = HouseholdSyncService(
      auth: ref.watch(firebaseAuthProvider),
      itemDao: ref.watch(itemDaoProvider),
      historyDao: ref.watch(historyDaoProvider),
      pendingSyncDao: ref.watch(pendingSyncDaoProvider),
      syncCheckpointDao: ref.watch(syncCheckpointDaoProvider),
      householdCloudService: ref.watch(householdCloudServiceProvider),
      itemCloudMediaService: ref.watch(itemCloudMediaServiceProvider),
      cloudObservationService: ref.watch(cloudObservationServiceProvider),
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

final locationHierarchyMigrationServiceProvider =
    Provider<LocationHierarchyMigrationService>(
  (ref) => LocationHierarchyMigrationService(
    itemDao: ref.watch(itemDaoProvider),
    locationDao: ref.watch(locationDaoProvider),
  ),
);

/// Runs the Phase-5 hierarchy migration once on app startup.
/// Backfills [area_uuid] / [room_uuid] on items that predate the new schema.
final locationHierarchyMigrationProvider = FutureProvider<int>((ref) async {
  return ref.read(locationHierarchyMigrationServiceProvider).migrate();
});
