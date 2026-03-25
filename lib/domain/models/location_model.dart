enum LocationType {
  area,
  room,
  zone;

  String get value => switch (this) {
        LocationType.area => 'area',
        LocationType.room => 'room',
        LocationType.zone => 'zone',
      };

  String get label => switch (this) {
        LocationType.area => 'Area',
        LocationType.room => 'Room',
        LocationType.zone => 'Zone',
      };

  bool get canContainChildren => this != LocationType.zone;
  bool get canBeItemLocation => this == LocationType.zone;

  static LocationType fromStorage(
    String? raw, {
    String? parentUuid,
  }) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'area':
        return LocationType.area;
      case 'room':
        return LocationType.room;
      case 'zone':
        return LocationType.zone;
      default:
        return parentUuid == null ? LocationType.area : LocationType.zone;
    }
  }
}

class LocationModel {
  const LocationModel({
    required this.uuid,
    required this.name,
    required this.createdAt,
    required this.type,
    this.fullPath,
    this.parentUuid,
    this.iconName = 'folder',
    this.usageCount = 0,
  });

  final String uuid;
  final String name;
  final LocationType type;

  /// Breadcrumb path e.g. "Home > Bedroom > Top Shelf"
  final String? fullPath;
  final String? parentUuid;

  /// Material icon name string (used with Icon widget via lookup)
  final String iconName;

  /// How many times this location has been used as an item's location.
  final int usageCount;
  final DateTime createdAt;

  bool get isRoot => parentUuid == null;
  bool get isArea => type == LocationType.area;
  bool get isRoom => type == LocationType.room;
  bool get isZone => type == LocationType.zone;
  bool get isAssignableToItem => type.canBeItemLocation;

  /// The display label — same as [name] but aliased for clarity in UI.
  String get displayName => name;

  LocationModel copyWith({
    String? uuid,
    String? name,
    LocationType? type,
    String? fullPath,
    String? parentUuid,
    String? iconName,
    int? usageCount,
    DateTime? createdAt,
    bool clearParentUuid = false,
  }) {
    return LocationModel(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      type: type ?? this.type,
      fullPath: fullPath ?? this.fullPath,
      parentUuid: clearParentUuid ? null : (parentUuid ?? this.parentUuid),
      iconName: iconName ?? this.iconName,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'name': name,
      'location_type': type.value,
      'full_path': fullPath,
      'parent_uuid': parentUuid,
      'icon_name': iconName,
      'usage_count': usageCount,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory LocationModel.fromMap(Map<String, dynamic> map) {
    return LocationModel(
      uuid: map['uuid'] as String,
      name: map['name'] as String,
      type: LocationType.fromStorage(
        map['location_type'] as String?,
        parentUuid: map['parent_uuid'] as String?,
      ),
      fullPath: map['full_path'] as String?,
      parentUuid: map['parent_uuid'] as String?,
      iconName: map['icon_name'] as String? ?? 'folder',
      usageCount: map['usage_count'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'type': type.value,
      'fullPath': fullPath,
      'parentUuid': parentUuid,
      'iconName': iconName,
      'usageCount': usageCount,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is LocationModel && other.uuid == uuid);

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() =>
      'LocationModel(uuid: $uuid, name: $name, type: ${type.value}, path: $fullPath)';
}
