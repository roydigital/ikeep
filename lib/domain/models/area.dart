import 'location_model.dart';

/// Represents the top-level building or property in the location hierarchy.
///
/// Hierarchy: **Area → Room → Zone**
///
/// Examples: House, Office, Garage, Storage Unit.
///
/// Persistence: backed by the existing [locations] SQLite table with
/// [LocationType.area]. Use [toLocation] / [fromLocation] to convert.
class Area {
  const Area({
    required this.uuid,
    required this.name,
    required this.createdAt,
    this.iconName = 'home_work',
    this.usageCount = 0,
  });

  final String uuid;
  final String name;

  /// Material icon name (resolved in UI via a lookup map).
  final String iconName;

  /// How many items (via rooms/zones) belong to this area.
  /// Derived at query time; not stored on the model itself.
  final int usageCount;

  final DateTime createdAt;

  // ── Factories ──────────────────────────────────────────────────────────────

  /// Creates an [Area] from the existing flat [LocationModel].
  /// The [location] must have [LocationType.area].
  factory Area.fromLocation(LocationModel location) {
    assert(
      location.type == LocationType.area,
      'Area.fromLocation: expected type=area, got ${location.type}',
    );
    return Area(
      uuid: location.uuid,
      name: location.name,
      iconName: location.iconName,
      usageCount: location.usageCount,
      createdAt: location.createdAt,
    );
  }

  // ── Conversions ────────────────────────────────────────────────────────────

  /// Converts back to [LocationModel] for persistence in the `locations` table.
  LocationModel toLocation() {
    return LocationModel(
      uuid: uuid,
      name: name,
      type: LocationType.area,
      // Areas are root nodes — no parent.
      parentUuid: null,
      fullPath: name,
      iconName: iconName,
      usageCount: usageCount,
      createdAt: createdAt,
    );
  }

  // ── Mutation ───────────────────────────────────────────────────────────────

  Area copyWith({
    String? uuid,
    String? name,
    String? iconName,
    int? usageCount,
    DateTime? createdAt,
  }) {
    return Area(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ── Equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Area && other.uuid == uuid);

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() => 'Area(uuid: $uuid, name: $name)';
}
