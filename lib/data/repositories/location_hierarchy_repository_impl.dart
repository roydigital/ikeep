import '../../core/errors/failure.dart';
import '../../domain/models/area.dart';
import '../../domain/models/location_model.dart';
import '../../domain/models/room.dart';
import '../../domain/models/zone.dart';
import '../database/location_dao.dart';
import 'location_hierarchy_repository.dart';
import 'location_repository.dart';

/// Concrete implementation of [LocationHierarchyRepository].
///
/// **Reads** are handled directly by [LocationDao] with type filters and
/// then converted to typed domain models via their factory constructors.
///
/// **Writes** delegate to [LocationRepository] to reuse its path-building
/// logic ([LocationRepositoryImpl._buildFullPathForLocation]). We simply call
/// `typedModel.toLocation()` to convert back to a [LocationModel] first.
class LocationHierarchyRepositoryImpl implements LocationHierarchyRepository {
  const LocationHierarchyRepositoryImpl({
    required this.locationDao,
    required this.locationRepository,
  });

  final LocationDao locationDao;

  /// Used only for write operations — delegates path-building here.
  final LocationRepository locationRepository;

  // ── Read helpers ──────────────────────────────────────────────────────────

  /// Filters a list of [LocationModel] rows to a specific [LocationType]
  /// and maps each one through [convert].
  List<T> _mapFiltered<T>(
    List<LocationModel> rows,
    LocationType type,
    T Function(LocationModel) convert,
  ) =>
      rows
          .where((loc) => loc.type == type)
          .map(convert)
          .toList();

  // ── Read ──────────────────────────────────────────────────────────────────

  @override
  Future<List<Area>> getAreas() async {
    // Root locations (no parent) are always areas.
    final rows = await locationDao.getRootLocations();
    return _mapFiltered(rows, LocationType.area, Area.fromLocation);
  }

  @override
  Future<List<Room>> getRoomsForArea(String areaUuid) async {
    final children = await locationDao.getChildLocations(areaUuid);
    final areaRow = await locationDao.getLocationByUuid(areaUuid);
    final areaName = areaRow?.name;

    return _mapFiltered(
      children,
      LocationType.room,
      (loc) => Room.fromLocation(loc, areaName: areaName),
    );
  }

  @override
  Future<List<Zone>> getZonesForRoom(String roomUuid) async {
    final children = await locationDao.getChildLocations(roomUuid);
    final roomRow = await locationDao.getLocationByUuid(roomUuid);
    final areaRow = roomRow?.parentUuid == null
        ? null
        : await locationDao.getLocationByUuid(roomRow!.parentUuid!);

    return _mapFiltered(
      children,
      LocationType.zone,
      (loc) => Zone.fromLocationWithParents(
        location: loc,
        parent: roomRow,
        grandparent: areaRow,
      ),
    );
  }

  @override
  Future<List<Zone>> getDirectZonesForArea(String areaUuid) async {
    final children = await locationDao.getChildLocations(areaUuid);
    final areaRow = await locationDao.getLocationByUuid(areaUuid);

    // Direct zones: children of the area that are themselves zones (not rooms).
    return _mapFiltered(
      children,
      LocationType.zone,
      (loc) => Zone.fromLocationWithParents(
        location: loc,
        parent: areaRow, // parent is the area itself
        grandparent: null, // no grandparent — area IS the top level
      ),
    );
  }

  @override
  Future<Zone?> resolveZone(String zoneUuid) async {
    // getAncestors returns the full chain from root down to (and including)
    // the requested node. e.g. [Area, Room, Zone] or [Area, Zone].
    final ancestors = await locationDao.getAncestors(zoneUuid);
    if (ancestors.isEmpty) return null;

    final zone = ancestors.last;
    if (zone.type != LocationType.zone) return null;

    // Determine parents from the ancestor chain.
    final parent = ancestors.length >= 2 ? ancestors[ancestors.length - 2] : null;
    final grandparent =
        ancestors.length >= 3 ? ancestors[ancestors.length - 3] : null;

    return Zone.fromLocationWithParents(
      location: zone,
      parent: parent,
      grandparent: grandparent,
    );
  }

  // ── Write ─────────────────────────────────────────────────────────────────
  // All write paths call typedModel.toLocation() then pass to LocationRepository
  // so that full-path computation and sync hooks are automatically applied.

  @override
  Future<Failure?> saveArea(Area area) =>
      locationRepository.saveLocation(area.toLocation());

  @override
  Future<Failure?> saveRoom(Room room) =>
      locationRepository.saveLocation(room.toLocation());

  @override
  Future<Failure?> saveZone(Zone zone) =>
      locationRepository.saveLocation(zone.toLocation());

  @override
  Future<Failure?> updateArea(Area area) =>
      locationRepository.updateLocation(area.toLocation());

  @override
  Future<Failure?> updateRoom(Room room) =>
      locationRepository.updateLocation(room.toLocation());

  @override
  Future<Failure?> updateZone(Zone zone) =>
      locationRepository.updateLocation(zone.toLocation());

  @override
  Future<Failure?> deleteArea(String areaUuid) =>
      locationRepository.deleteLocation(areaUuid);

  @override
  Future<Failure?> deleteRoom(String roomUuid) =>
      locationRepository.deleteLocation(roomUuid);

  @override
  Future<Failure?> deleteZone(String zoneUuid) =>
      locationRepository.deleteLocation(zoneUuid);
}
