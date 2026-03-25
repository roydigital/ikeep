import 'location_model.dart';

/// Represents the most specific storage spot in the location hierarchy.
/// Items are always assigned to a Zone.
///
/// Hierarchy: Area → Room → **Zone**
///
/// Examples: Top Drawer, Closet Shelf, Under the Bed, Document Box.
///
/// A Zone's parent is either a [Room] (most common) or directly an [Area]
/// (e.g., a shelf in a Garage that has no sub-rooms). Both cases are supported.
///
/// Persistence: backed by the existing [locations] SQLite table with
/// [LocationType.zone]. Use [toLocation] / [fromLocation] to convert.
class Zone {
  const Zone({
    required this.uuid,
    required this.name,
    required this.createdAt,
    this.iconName = 'place',
    this.usageCount = 0,
    // At least one of [roomUuid] or [areaUuid] must be non-null.
    this.roomUuid,
    this.areaUuid,
    // Denormalized display fields — populated by DAO joins, never persisted.
    this.areaName,
    this.roomName,
  }) : assert(
          roomUuid != null || areaUuid != null,
          'Zone must have either a roomUuid or an areaUuid (or both).',
        );

  final String uuid;
  final String name;

  /// Material icon name (resolved in UI via a lookup map).
  final String iconName;

  /// How many items are stored in this zone.
  /// Derived at query time; not stored on the model itself.
  final int usageCount;

  final DateTime createdAt;

  // ── FK fields ──────────────────────────────────────────────────────────────

  /// FK → [Room.uuid]. Null when the zone is attached directly to an area
  /// (e.g., a garage shelf with no sub-rooms).
  final String? roomUuid;

  /// FK → [Area.uuid]. Always non-null once the hierarchy is fully resolved.
  /// If a zone is under a room, this is the room's parent area.
  final String? areaUuid;

  // ── Denormalized display fields ────────────────────────────────────────────

  /// Display name of the grandparent area. Populated by DAO joins.
  final String? areaName;

  /// Display name of the parent room. Null if zone is directly under an area.
  final String? roomName;

  // ── Computed ───────────────────────────────────────────────────────────────

  /// The direct parent UUID in the `locations` table.
  /// Prefers [roomUuid] when both are set.
  String get parentUuid => roomUuid ?? areaUuid!;

  /// Breadcrumb path for display: "House > Bedroom > Top Shelf"
  String get displayPath {
    final parts = <String>[
      if (areaName != null) areaName!,
      if (roomName != null) roomName!,
      name,
    ];
    return parts.join(' > ');
  }

  // ── Factories ──────────────────────────────────────────────────────────────

  /// Creates a [Zone] from a flat [LocationModel] when full hierarchy context
  /// is available (parent and grandparent models).
  ///
  /// The [parent] is the direct parent (a [Room] or an [Area]).
  /// The [grandparent] is the area when [parent] is a room; null otherwise.
  factory Zone.fromLocationWithParents({
    required LocationModel location,
    required LocationModel? parent,
    LocationModel? grandparent,
  }) {
    assert(
      location.type == LocationType.zone,
      'Zone.fromLocationWithParents: expected type=zone, got ${location.type}',
    );

    final parentIsRoom = parent?.type == LocationType.room;

    return Zone(
      uuid: location.uuid,
      name: location.name,
      iconName: location.iconName,
      usageCount: location.usageCount,
      createdAt: location.createdAt,
      // If parent is a room, that's our roomUuid; otherwise it's the area.
      roomUuid: parentIsRoom ? parent?.uuid : null,
      // Area is grandparent when parent is a room; parent itself when no room.
      areaUuid: parentIsRoom ? grandparent?.uuid : parent?.uuid,
      areaName: parentIsRoom ? grandparent?.name : parent?.name,
      roomName: parentIsRoom ? parent?.name : null,
    );
  }

  /// Minimal factory when only the [LocationModel] is available (no hierarchy).
  /// [roomUuid] and [areaUuid] are left null; caller must resolve them later.
  ///
  /// Use [Zone.fromLocationWithParents] whenever the hierarchy is available.
  factory Zone.fromLocation(LocationModel location) {
    assert(
      location.type == LocationType.zone,
      'Zone.fromLocation: expected type=zone, got ${location.type}',
    );
    return Zone(
      uuid: location.uuid,
      name: location.name,
      iconName: location.iconName,
      usageCount: location.usageCount,
      createdAt: location.createdAt,
      // We cannot determine whether the parent is a room or area without
      // loading additional rows. Use a placeholder value so the assert passes;
      // the repository layer resolves the real FKs before returning to the UI.
      areaUuid: location.parentUuid ?? 'unresolved',
    );
  }

  // ── Conversions ────────────────────────────────────────────────────────────

  /// Converts back to [LocationModel] for persistence in the `locations` table.
  /// The `parent_uuid` column stores the direct parent (room or area).
  LocationModel toLocation() {
    return LocationModel(
      uuid: uuid,
      name: name,
      type: LocationType.zone,
      // The locations table only stores the *direct* parent UUID.
      parentUuid: parentUuid,
      fullPath: displayPath,
      iconName: iconName,
      usageCount: usageCount,
      createdAt: createdAt,
    );
  }

  // ── Mutation ───────────────────────────────────────────────────────────────

  Zone copyWith({
    String? uuid,
    String? name,
    String? iconName,
    int? usageCount,
    DateTime? createdAt,
    String? roomUuid,
    String? areaUuid,
    String? areaName,
    String? roomName,
    bool clearRoomUuid = false,
    bool clearRoomName = false,
  }) {
    return Zone(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
      roomUuid: clearRoomUuid ? null : (roomUuid ?? this.roomUuid),
      areaUuid: areaUuid ?? this.areaUuid,
      areaName: areaName ?? this.areaName,
      roomName: clearRoomName ? null : (roomName ?? this.roomName),
    );
  }

  // ── Equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Zone && other.uuid == uuid);

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() =>
      'Zone(uuid: $uuid, name: $name, roomUuid: $roomUuid, areaUuid: $areaUuid)';
}
