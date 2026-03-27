import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database_helper.dart';
import '../data/database/borrow_request_dao.dart';
import '../data/database/cloud_observation_dao.dart';
import '../data/database/cloud_usage_snapshot_dao.dart';
import '../data/database/history_dao.dart';
import '../data/database/household_dao.dart';
import '../data/database/household_member_dao.dart';
import '../data/database/item_dao.dart';
import '../data/database/item_cloud_media_dao.dart';
import '../data/database/location_dao.dart';
import '../data/database/media_cache_dao.dart';
import '../data/database/pending_sync_dao.dart';
import '../data/database/sync_checkpoint_dao.dart';

final databaseHelperProvider = Provider<DatabaseHelper>(
  (ref) => DatabaseHelper.instance,
);

final itemDaoProvider = Provider<ItemDao>(
  (ref) => ItemDao(ref.watch(databaseHelperProvider)),
);

final locationDaoProvider = Provider<LocationDao>(
  (ref) => LocationDao(ref.watch(databaseHelperProvider)),
);

final historyDaoProvider = Provider<HistoryDao>(
  (ref) => HistoryDao(ref.watch(databaseHelperProvider)),
);

final householdDaoProvider = Provider<HouseholdDao>(
  (ref) => HouseholdDao(ref.watch(databaseHelperProvider)),
);

final borrowRequestDaoProvider = Provider<BorrowRequestDao>(
  (ref) => BorrowRequestDao(ref.watch(databaseHelperProvider)),
);

final pendingSyncDaoProvider = Provider<PendingSyncDao>(
  (ref) => PendingSyncDao(ref.watch(databaseHelperProvider)),
);

final householdMemberDaoProvider = Provider<HouseholdMemberDao>(
  (ref) => HouseholdMemberDao(ref.watch(databaseHelperProvider)),
);

final mediaCacheDaoProvider = Provider<MediaCacheDao>(
  (ref) => MediaCacheDao(ref.watch(databaseHelperProvider)),
);

final itemCloudMediaDaoProvider = Provider<ItemCloudMediaDao>(
  (ref) => ItemCloudMediaDao(ref.watch(databaseHelperProvider)),
);

final syncCheckpointDaoProvider = Provider<SyncCheckpointDao>(
  (ref) => SyncCheckpointDao(ref.watch(databaseHelperProvider)),
);

final cloudUsageSnapshotDaoProvider = Provider<CloudUsageSnapshotDao>(
  (ref) => CloudUsageSnapshotDao(ref.watch(databaseHelperProvider)),
);

final cloudObservationDaoProvider = Provider<CloudObservationDao>(
  (ref) => CloudObservationDao(ref.watch(databaseHelperProvider)),
);
