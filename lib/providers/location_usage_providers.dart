import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/item.dart';
import '../domain/models/location_model.dart';
import 'item_providers.dart';
import 'location_providers.dart';

final locationsWithDerivedUsageProvider =
    FutureProvider<List<LocationModel>>((ref) async {
  final locations = await ref.watch(allLocationsProvider.future);
  final items = await ref.watch(allItemsProvider.future);
  return _applyDerivedUsageCounts(locations, items);
});

List<LocationModel> _applyDerivedUsageCounts(
  List<LocationModel> locations,
  List<Item> items,
) {
  final parentByUuid = <String, String?>{
    for (final location in locations) location.uuid: location.parentUuid,
  };
  final countsByUuid = <String, int>{};

  for (final item in items) {
    if (item.isArchived) continue;

    // Prefer the new canonical zoneUuid; fall back to legacy locationUuid for
    // items not yet run through the Phase-5 migration.
    var currentUuid = item.zoneUuid ?? item.locationUuid;
    final visited = <String>{};

    while (currentUuid != null && visited.add(currentUuid)) {
      if (!parentByUuid.containsKey(currentUuid)) break;
      countsByUuid[currentUuid] = (countsByUuid[currentUuid] ?? 0) + 1;
      currentUuid = parentByUuid[currentUuid];
    }
  }

  return locations
      .map(
        (location) => location.copyWith(
          usageCount: countsByUuid[location.uuid] ?? 0,
        ),
      )
      .toList();
}
