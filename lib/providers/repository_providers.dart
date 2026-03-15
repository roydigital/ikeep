import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/history_repository.dart';
import '../data/repositories/history_repository_impl.dart';
import '../data/repositories/item_repository.dart';
import '../data/repositories/item_repository_impl.dart';
import '../data/repositories/location_repository.dart';
import '../data/repositories/location_repository_impl.dart';
import 'database_provider.dart';

final itemRepositoryProvider = Provider<ItemRepository>(
  (ref) => ItemRepositoryImpl(
    itemDao: ref.watch(itemDaoProvider),
    locationDao: ref.watch(locationDaoProvider),
    historyDao: ref.watch(historyDaoProvider),
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
  ),
);
