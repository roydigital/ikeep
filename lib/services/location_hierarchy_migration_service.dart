import '../core/utils/location_hierarchy_utils.dart';
import '../data/database/item_dao.dart';
import '../data/database/location_dao.dart';

/// Phase-5 migration: backfills [area_uuid] and [room_uuid] on all items that
/// already have a [zone_uuid] (or legacy [location_uuid]) set, but whose
/// [area_uuid] / [room_uuid] columns are still null.
///
/// Safe to run repeatedly — it only touches items that are missing the fields.
/// Returns the number of items that were updated.
class LocationHierarchyMigrationService {
  const LocationHierarchyMigrationService({
    required ItemDao itemDao,
    required LocationDao locationDao,
  })  : _itemDao = itemDao,
        _locationDao = locationDao;

  final ItemDao _itemDao;
  final LocationDao _locationDao;

  Future<int> migrate() async {
    // Load the full location tree and build a hierarchy index.
    final allLocations = await _locationDao.getAllLocations();
    if (allLocations.isEmpty) return 0;
    final hierarchy = LocationHierarchy.fromLocations(allLocations);

    // Load all items (active + archived) so the migration is complete.
    final activeItems = await _itemDao.getAllItems();
    final archivedItems = await _itemDao.getArchivedItems();
    final allItems = [...activeItems, ...archivedItems];

    int migratedCount = 0;

    for (final item in allItems) {
      // Determine which zone UUID this item refers to.
      final zoneUuid = item.zoneUuid ?? item.locationUuid;
      if (zoneUuid == null) continue;

      // Skip if already fully backfilled.
      if (item.areaUuid != null && item.roomUuid != null) continue;

      // Resolve ancestry.
      final area = hierarchy.areaFor(zoneUuid);
      final room = hierarchy.roomFor(zoneUuid);

      // No change needed if the hierarchy can't resolve them.
      if (area == null && room == null) continue;

      // Only write if something actually needs updating.
      final resolvedAreaUuid = (item.areaUuid == null && area != null)
          ? area.uuid
          : item.areaUuid;
      final resolvedRoomUuid = (item.roomUuid == null && room != null)
          ? room.uuid
          : item.roomUuid;

      if (resolvedAreaUuid == item.areaUuid && resolvedRoomUuid == item.roomUuid) {
        continue;
      }

      await _itemDao.updateItem(
        item.copyWith(
          areaUuid: resolvedAreaUuid,
          roomUuid: resolvedRoomUuid,
          // Also ensure zone_uuid is set for items that only had location_uuid.
          zoneUuid: item.zoneUuid ?? zoneUuid,
        ),
      );

      migratedCount++;
    }

    return migratedCount;
  }
}
