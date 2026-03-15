import 'dart:convert';

class Item {
  const Item({
    required this.uuid,
    required this.name,
    required this.savedAt,
    this.locationUuid,
    this.imagePaths = const [],
    this.tags = const [],
    this.updatedAt,
    this.latitude,
    this.longitude,
    this.expiryDate,
    this.isArchived = false,
    this.notes,
    this.cloudId,
    this.lastSyncedAt,
    // Denormalized for display — populated by joins
    this.locationName,
    this.locationFullPath,
  });

  final String uuid;
  final String name;
  final String? locationUuid;
  final List<String> imagePaths;
  final List<String> tags;
  final DateTime savedAt;
  final DateTime? updatedAt;
  final double? latitude;
  final double? longitude;
  final DateTime? expiryDate;
  final bool isArchived;
  final String? notes;
  final String? cloudId;
  final DateTime? lastSyncedAt;

  // Joined display fields (not persisted in items table)
  final String? locationName;
  final String? locationFullPath;

  Item copyWith({
    String? uuid,
    String? name,
    String? locationUuid,
    List<String>? imagePaths,
    List<String>? tags,
    DateTime? savedAt,
    DateTime? updatedAt,
    double? latitude,
    double? longitude,
    DateTime? expiryDate,
    bool? isArchived,
    String? notes,
    String? cloudId,
    DateTime? lastSyncedAt,
    String? locationName,
    String? locationFullPath,
    bool clearLocationUuid = false,
    bool clearExpiryDate = false,
    bool clearNotes = false,
  }) {
    return Item(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      locationUuid: clearLocationUuid ? null : (locationUuid ?? this.locationUuid),
      imagePaths: imagePaths ?? this.imagePaths,
      tags: tags ?? this.tags,
      savedAt: savedAt ?? this.savedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      isArchived: isArchived ?? this.isArchived,
      notes: clearNotes ? null : (notes ?? this.notes),
      cloudId: cloudId ?? this.cloudId,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      locationName: locationName ?? this.locationName,
      locationFullPath: locationFullPath ?? this.locationFullPath,
    );
  }

  /// Converts to a map for SQLite insertion. Does NOT include joined fields.
  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'name': name,
      'location_uuid': locationUuid,
      'image_paths': jsonEncode(imagePaths),
      'tags': jsonEncode(tags),
      'saved_at': savedAt.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'latitude': latitude,
      'longitude': longitude,
      'expiry_date': expiryDate?.millisecondsSinceEpoch,
      'is_archived': isArchived ? 1 : 0,
      'notes': notes,
      'cloud_id': cloudId,
      'last_synced_at': lastSyncedAt?.millisecondsSinceEpoch,
    };
  }

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      uuid: map['uuid'] as String,
      name: map['name'] as String,
      locationUuid: map['location_uuid'] as String?,
      imagePaths: List<String>.from(
        jsonDecode(map['image_paths'] as String? ?? '[]') as List,
      ),
      tags: List<String>.from(
        jsonDecode(map['tags'] as String? ?? '[]') as List,
      ),
      savedAt: DateTime.fromMillisecondsSinceEpoch(map['saved_at'] as int),
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      expiryDate: map['expiry_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expiry_date'] as int)
          : null,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      notes: map['notes'] as String?,
      cloudId: map['cloud_id'] as String?,
      lastSyncedAt: map['last_synced_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_synced_at'] as int)
          : null,
      // Joined fields from queries
      locationName: map['location_name'] as String?,
      locationFullPath: map['location_full_path'] as String?,
    );
  }

  /// Converts to JSON for Appwrite sync. Excludes joined display fields.
  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'locationUuid': locationUuid,
      'imagePaths': imagePaths,
      'tags': tags,
      'savedAt': savedAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'expiryDate': expiryDate?.toIso8601String(),
      'isArchived': isArchived,
      'notes': notes,
    };
  }

  @override
  String toString() => 'Item(uuid: $uuid, name: $name, location: $locationUuid)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Item && other.uuid == uuid);

  @override
  int get hashCode => uuid.hashCode;
}
