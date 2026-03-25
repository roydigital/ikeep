import '../../core/errors/failure.dart';
import '../../domain/models/area.dart';
import '../../domain/models/room.dart';
import '../../domain/models/zone.dart';

/// Repository for the strict Area → Room → Zone location hierarchy.
///
/// All read methods return typed domain models ([Area], [Room], [Zone]).
/// Write methods accept typed models and return a [Failure] on error (null = ok).
///
/// The underlying storage is still the single `locations` SQLite table —
/// this repository is just a typed lens over it.
abstract class LocationHierarchyRepository {
  // ── Read ──────────────────────────────────────────────────────────────────

  /// All top-level areas, ordered by usage count desc then name asc.
  Future<List<Area>> getAreas();

  /// All rooms that belong to [areaUuid], ordered by name.
  Future<List<Room>> getRoomsForArea(String areaUuid);

  /// Zones whose direct parent is [roomUuid], ordered by name.
  Future<List<Zone>> getZonesForRoom(String roomUuid);

  /// Zones whose direct parent is an area (no room in between), ordered by name.
  /// These are "direct area zones" — useful for Garages, Storerooms, etc.
  Future<List<Zone>> getDirectZonesForArea(String areaUuid);

  /// Resolves a [Zone] by UUID with full hierarchy populated
  /// ([Zone.areaUuid], [Zone.roomUuid], [Zone.areaName], [Zone.roomName]).
  /// Returns null if the UUID does not exist or is not a zone.
  Future<Zone?> resolveZone(String zoneUuid);

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<Failure?> saveArea(Area area);
  Future<Failure?> saveRoom(Room room);
  Future<Failure?> saveZone(Zone zone);

  Future<Failure?> updateArea(Area area);
  Future<Failure?> updateRoom(Room room);
  Future<Failure?> updateZone(Zone zone);

  /// Deletes and cascades to all children (ON DELETE CASCADE in SQLite).
  Future<Failure?> deleteArea(String areaUuid);
  Future<Failure?> deleteRoom(String roomUuid);
  Future<Failure?> deleteZone(String zoneUuid);
}
