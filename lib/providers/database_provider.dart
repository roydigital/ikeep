import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database_helper.dart';
import '../data/database/history_dao.dart';
import '../data/database/item_dao.dart';
import '../data/database/location_dao.dart';

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
