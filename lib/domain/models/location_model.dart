class LocationModel {
  const LocationModel({
    required this.uuid,
    required this.name,
    required this.createdAt,
    this.fullPath,
    this.parentUuid,
    this.iconName = 'folder',
    this.usageCount = 0,
  });

  final String uuid;
  final String name;

  /// Breadcrumb path e.g. "Home > Bedroom > Top Shelf"
  final String? fullPath;
  final String? parentUuid;

  /// Material icon name string (used with Icon widget via lookup)
  final String iconName;

  /// How many times this location has been used as an item's location.
  final int usageCount;
  final DateTime createdAt;

  bool get isRoot => parentUuid == null;

  /// The display label — same as [name] but aliased for clarity in UI.
  String get displayName => name;

  LocationModel copyWith({
    String? uuid,
    String? name,
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
  String toString() => 'LocationModel(uuid: $uuid, name: $name, path: $fullPath)';
}
