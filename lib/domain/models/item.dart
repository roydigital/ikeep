import 'dart:convert';

import 'item_visibility.dart';

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
    this.isLent = false,
    this.lentTo,
    this.lentOn,
    this.expectedReturnDate,
    this.seasonCategory = 'all_year',
    this.lentReminderAfterDays,
    this.isAvailableForLending = false,
    this.visibility = ItemVisibility.private_,
    this.householdId,
    this.sharedWithMemberUuids = const [],
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
  final bool isLent;
  final String? lentTo;
  final DateTime? lentOn;
  final DateTime? expectedReturnDate;
  final String seasonCategory;
  final int? lentReminderAfterDays;
  final bool isAvailableForLending;
  final ItemVisibility visibility;
  final String? householdId;
  final List<String> sharedWithMemberUuids;

  /// Social sharing is currently disabled in the app.
  bool get isShared => false;

  /// Nearby sharing is currently disabled in the app.
  bool get isNearby => false;

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
    bool? isLent,
    String? lentTo,
    DateTime? lentOn,
    DateTime? expectedReturnDate,
    String? seasonCategory,
    int? lentReminderAfterDays,
    bool? isAvailableForLending,
    ItemVisibility? visibility,
    String? householdId,
    List<String>? sharedWithMemberUuids,
    String? locationName,
    String? locationFullPath,
    bool clearLocationUuid = false,
    bool clearHouseholdId = false,
    bool clearExpiryDate = false,
    bool clearNotes = false,
    bool clearLentTo = false,
    bool clearLentOn = false,
    bool clearExpectedReturnDate = false,
    bool clearLentReminderAfterDays = false,
  }) {
    return Item(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      locationUuid:
          clearLocationUuid ? null : (locationUuid ?? this.locationUuid),
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
      isLent: isLent ?? this.isLent,
      lentTo: clearLentTo ? null : (lentTo ?? this.lentTo),
      lentOn: clearLentOn ? null : (lentOn ?? this.lentOn),
      expectedReturnDate: clearExpectedReturnDate
          ? null
          : (expectedReturnDate ?? this.expectedReturnDate),
      seasonCategory: seasonCategory ?? this.seasonCategory,
      lentReminderAfterDays: clearLentReminderAfterDays
          ? null
          : (lentReminderAfterDays ?? this.lentReminderAfterDays),
      isAvailableForLending:
          isAvailableForLending ?? this.isAvailableForLending,
      visibility: visibility ?? this.visibility,
      householdId: clearHouseholdId ? null : (householdId ?? this.householdId),
      sharedWithMemberUuids:
          sharedWithMemberUuids ?? this.sharedWithMemberUuids,
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
      'is_lent': isLent ? 1 : 0,
      'lent_to': lentTo,
      'lent_on': lentOn?.millisecondsSinceEpoch,
      'expected_return_date': expectedReturnDate?.millisecondsSinceEpoch,
      'season_category': seasonCategory,
      'lent_reminder_after_days': lentReminderAfterDays,
      'is_available_for_lending': isAvailableForLending ? 1 : 0,
      'visibility': visibility.value,
      'household_id': householdId,
      'shared_with_member_uuids': jsonEncode(sharedWithMemberUuids),
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
      isLent: (map['is_lent'] as int? ?? 0) == 1,
      lentTo: map['lent_to'] as String?,
      lentOn: map['lent_on'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lent_on'] as int)
          : null,
      expectedReturnDate: map['expected_return_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              map['expected_return_date'] as int,
            )
          : null,
      seasonCategory: (map['season_category'] as String?) ?? 'all_year',
      lentReminderAfterDays: map['lent_reminder_after_days'] as int?,
      isAvailableForLending:
          (map['is_available_for_lending'] as int? ?? 0) == 1,
      visibility:
          ItemVisibility.fromString(map['visibility'] as String?),
      householdId:
          map['household_id'] as String? ?? map['householdId'] as String?,
      sharedWithMemberUuids: List<String>.from(
        jsonDecode(
          map['shared_with_member_uuids'] as String? ??
              map['sharedWithMemberUuids'] as String? ??
              '[]',
        ) as List,
      ),
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
      'isLent': isLent,
      'lentTo': lentTo,
      'lentOn': lentOn?.toIso8601String(),
      'expectedReturnDate': expectedReturnDate?.toIso8601String(),
      'seasonCategory': seasonCategory,
      'lentReminderAfterDays': lentReminderAfterDays,
      'isAvailableForLending': isAvailableForLending,
      'visibility': visibility.value,
      'householdId': householdId,
      'sharedWithMemberUuids': sharedWithMemberUuids,
    };
  }

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      locationUuid: json['locationUuid'] as String?,
      imagePaths: List<String>.from(
        json['imagePaths'] as List<dynamic>? ?? const <dynamic>[],
      ),
      tags: List<String>.from(
        json['tags'] as List<dynamic>? ?? const <dynamic>[],
      ),
      savedAt: DateTime.parse(json['savedAt'] as String),
      updatedAt: _dateTimeFromJson(json['updatedAt']),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      expiryDate: _dateTimeFromJson(json['expiryDate']),
      isArchived: json['isArchived'] as bool? ?? false,
      notes: json['notes'] as String?,
      cloudId: json['cloudId'] as String?,
      lastSyncedAt: _dateTimeFromJson(json['lastSyncedAt']),
      isLent: json['isLent'] as bool? ?? false,
      lentTo: json['lentTo'] as String?,
      lentOn: _dateTimeFromJson(json['lentOn']),
      expectedReturnDate: _dateTimeFromJson(json['expectedReturnDate']),
      seasonCategory: (json['seasonCategory'] as String?) ?? 'all_year',
      lentReminderAfterDays: json['lentReminderAfterDays'] as int?,
      isAvailableForLending: json['isAvailableForLending'] as bool? ?? false,
      visibility: ItemVisibility.fromString(json['visibility'] as String?),
      householdId: json['householdId'] as String?,
      sharedWithMemberUuids: List<String>.from(
        json['sharedWithMemberUuids'] as List<dynamic>? ?? const <dynamic>[],
      ),
    );
  }

  static DateTime? _dateTimeFromJson(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  @override
  String toString() =>
      'Item(uuid: $uuid, name: $name, location: $locationUuid)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Item && other.uuid == uuid);

  @override
  int get hashCode => uuid.hashCode;
}
