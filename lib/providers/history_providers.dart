import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/item_location_history.dart';
import 'repository_providers.dart';

final itemHistoryProvider =
    FutureProvider.family<List<ItemLocationHistory>, String>(
        (ref, itemUuid) async {
  return ref.watch(historyRepositoryProvider).getHistoryForItem(itemUuid);
});
