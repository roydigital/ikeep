import 'location_model.dart';

/// Represents a room inside an [Area] in the location hierarchy.
///
/// Hierarchy: Area → **Room** → Zone
///
/// Examples: Bedroom, Kitchen, Garage Bay, Server Room.
///
/// Persistence: backed by the existing [locations] SQLite table with
/// [LocationType.room]. Use [toLocation] / [fromLocation] to convert.
class Room {
  const Room({
    required this.uuid,
    required this.areaUuid,
    required this.name,
    required this.createdAt,
    this.iconName = 'meeting_room',
    this.usageCount = 0,
    // Denormalized — populated by DAO joins, never persisted on this model.
    this.areaName,
  });

  final String uuid;

  /// FK → [Area.uuid]. The room must always belong to an area.
  final String areaUuid;

  final String name;

  /// Material icon name (resolved in UI via a lookup map).
  final String iconName;

  /// How many items (via zones) belong to this room.
  /// Derived at query time; not stored on the model itself.
  final int usageCount;

  final DateTime createdAt;

  /// Display name of the parent area. Populated by DAO joins.
  /// Not persisted — derived from the [locations] table at read time.
  final String? areaName;

  // ── Computed ───────────────────────────────────────────────────────────────

  /// Breadcrumb path: "House > Bedroom"
  String get displayPath =>
      areaName != null ? '$areaName > $name' : name;

  // ── Factories ──────────────────────────────────────────────────────────────

  /// Creates a [Room] from the existing flat [LocationModel].
  /// The [location] must have [LocationType.room] and a non-null [parentUuid]
  /// (which is the area's UUID).
  factory Room.fromLocation(
    LocationModel location, {
    String? areaName,
  }) {
    assert(
      location.type == LocationType.room,
      'Room.fromLocation: expected type=room, got ${location.type}',
    );
    assert(
      location.parentUuid != null,
      'Room.fromLocation: rooms must have a parent area UUID',
    );
    return Room(
      uuid: location.uuid,
      areaUuid: location.parentUuid!,
      name: location.name,
      iconName: location.iconName,
      usageCount: location.usageCount,
      createdAt: location.createdAt,
      areaName: areaName,
    );
  }

  // ── Conversions ────────────────────────────────────────────────────────────

  /// Converts back to [LocationModel] for persistence in the `locations` table.
  LocationModel toLocation() {
    return LocationModel(
      uuid: uuid,
      name: name,
      type: LocationType.room,
      // The room's parent in the locations table is its area.
      parentUuid: areaUuid,
      fullPath: displayPath,
      iconName: iconName,
      usageCount: usageCount,
      createdAt: createdAt,
    );
  }

  // ── Mutation ───────────────────────────────────────────────────────────────

  Room copyWith({
    String? uuid,
    String? areaUuid,
    String? name,
    String? iconName,
    int? usageCount,
    DateTime? createdAt,
    String? areaName,
    bool clearAreaName = false,
  }) {
    return Room(
      uuid: uuid ?? this.uuid,
      areaUuid: areaUuid ?? this.areaUuid,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
      areaName: clearAreaName ? null : (areaName ?? this.areaName),
    );
  }

  // ── Equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Room && other.uuid == uuid);

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() =>
      'Room(uuid: $uuid, name: $name, areaUuid: $areaUuid)';
}
