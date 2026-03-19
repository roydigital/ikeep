import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/borrow_request_repository.dart';
import '../data/repositories/borrow_request_repository_impl.dart';
import '../data/repositories/history_repository.dart';
import '../data/repositories/history_repository_impl.dart';
import '../data/repositories/household_repository.dart';
import '../data/repositories/household_repository_impl.dart';
import '../data/repositories/item_repository.dart';
import '../data/repositories/item_repository_impl.dart';
import '../data/repositories/location_repository.dart';
import '../data/repositories/location_repository_impl.dart';
import 'database_provider.dart';
import 'service_providers.dart';

final itemRepositoryProvider = Provider<ItemRepository>(
  (ref) => ItemRepositoryImpl(
    itemDao: ref.watch(itemDaoProvider),
    locationDao: ref.watch(locationDaoProvider),
    historyDao: ref.watch(historyDaoProvider),
    householdCloudService: ref.watch(householdCloudServiceProvider),
  ),
);

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => LocationRepositoryImpl(
    locationDao: ref.watch(locationDaoProvider),
  ),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepositoryImpl(
    historyDao: ref.watch(historyDaoProvider),
    householdCloudService: ref.watch(householdCloudServiceProvider),
  ),
);

final borrowRequestRepositoryProvider = Provider<BorrowRequestRepository>(
  (ref) => BorrowRequestRepositoryImpl(
    borrowRequestDao: ref.watch(borrowRequestDaoProvider),
    itemDao: ref.watch(itemDaoProvider),
    historyDao: ref.watch(historyDaoProvider),
  ),
);

final householdRepositoryProvider = Provider<HouseholdRepository>(
  (ref) => HouseholdRepositoryImpl(
    householdDao: ref.watch(householdDaoProvider),
    memberDao: ref.watch(householdMemberDaoProvider),
    cloudService: ref.watch(householdCloudServiceProvider),
  ),
);
