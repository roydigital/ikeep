import 'dart:convert';

import 'item_visibility.dart';

class Item {
  const Item({
    required this.uuid,
    required this.name,
    required this.savedAt,
    // ── Legacy location field (kept for backward compat during migration) ──
    // Replaced by the three typed FK fields below. Will be removed in Phase 5
    // once all items have been migrated to use areaUuid/roomUuid/zoneUuid.
    this.locationUuid,
    // ── New hierarchical location FKs (Phase 1) ───────────────────────────
    // These point to rows in the `locations` table with the matching type.
    // zoneUuid is the primary "where is this item?" reference.
    // roomUuid and areaUuid allow efficient filtering without table joins.
    this.areaUuid,
    this.roomUuid,
    this.zoneUuid,
    this.imagePaths = const [],
    this.tags = const [],
    this.updatedAt,
    this.lastUpdatedAt,
    this.lastMovedAt,
    this.latitude,
    this.longitude,
    this.expiryDate,
    this.warrantyEndDate,
    this.isArchived = false,
    this.notes,
    this.invoicePath,
    this.invoiceFileName,
    this.invoiceFileSizeBytes,
    this.cloudId,
    this.lastSyncedAt,
    this.isBackedUp = false,
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
    // Denormalized for display — populated by joins, never persisted
    this.locationName,
    this.locationFullPath,
    this.areaName,
    this.roomName,
    this.zoneName,
  });

  final String uuid;
  final String name;

  // ── Legacy location field ──────────────────────────────────────────────────
  /// @deprecated Use [zoneUuid] + [roomUuid] + [areaUuid] instead.
  /// Retained for backward compatibility during the Phase-5 data migration.
  final String? locationUuid;

  // ── Hierarchical location FKs (Phase 1 refactor) ──────────────────────────
  /// FK → [Area.uuid] in the `locations` table. Allows filtering by area
  /// without any JOIN. Null until populated by Phase-5 migration.
  final String? areaUuid;

  /// FK → [Room.uuid] in the `locations` table. Null for zones directly
  /// under an area. Null until populated by Phase-5 migration.
  final String? roomUuid;

  /// FK → [Zone.uuid] in the `locations` table. This is the canonical
  /// "where is this item stored?" reference. Replaces [locationUuid].
  /// Null until populated by Phase-5 migration.
  final String? zoneUuid;

  final List<String> imagePaths;
  final List<String> tags;
  final DateTime savedAt;
  final DateTime? updatedAt;
  final DateTime? lastUpdatedAt;
  final DateTime? lastMovedAt;
  final double? latitude;
  final double? longitude;
  final DateTime? expiryDate;
  final DateTime? warrantyEndDate;
  final bool isArchived;
  final String? notes;
  final String? invoicePath;
  final String? invoiceFileName;
  final int? invoiceFileSizeBytes;
  final String? cloudId;
  final DateTime? lastSyncedAt;
  final bool isBackedUp;
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

  // ── Joined display fields (not persisted in items table) ─────────────────
  /// Legacy joined name from the old flat `locations` table.
  final String? locationName;

  /// Legacy joined path from the old flat `locations` table.
  final String? locationFullPath;

  /// Joined display name of the item's area. Populated by DAO queries.
  final String? areaName;

  /// Joined display name of the item's room. Null for direct-to-area zones.
  final String? roomName;

  /// Joined display name of the item's zone. Populated by DAO queries.
  final String? zoneName;

  Item copyWith({
    String? uuid,
    String? name,
    String? locationUuid,
    List<String>? imagePaths,
    List<String>? tags,
    DateTime? savedAt,
    DateTime? updatedAt,
    DateTime? lastUpdatedAt,
    DateTime? lastMovedAt,
    double? latitude,
    double? longitude,
    DateTime? expiryDate,
    DateTime? warrantyEndDate,
    bool? isArchived,
    String? notes,
    String? invoicePath,
    String? invoiceFileName,
    int? invoiceFileSizeBytes,
    String? cloudId,
    DateTime? lastSyncedAt,
    bool? isBackedUp,
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
    String? areaUuid,
    String? roomUuid,
    String? zoneUuid,
    String? areaName,
    String? roomName,
    String? zoneName,
    bool clearLocationUuid = false,
    bool clearAreaUuid = false,
    bool clearRoomUuid = false,
    bool clearZoneUuid = false,
    bool clearHouseholdId = false,
    bool clearExpiryDate = false,
    bool clearWarrantyEndDate = false,
    bool clearNotes = false,
    bool clearInvoicePath = false,
    bool clearInvoiceFileName = false,
    bool clearInvoiceFileSizeBytes = false,
    bool clearCloudId = false,
    bool clearLastSyncedAt = false,
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
      areaUuid: clearAreaUuid ? null : (areaUuid ?? this.areaUuid),
      roomUuid: clearRoomUuid ? null : (roomUuid ?? this.roomUuid),
      zoneUuid: clearZoneUuid ? null : (zoneUuid ?? this.zoneUuid),
      imagePaths: imagePaths ?? this.imagePaths,
      tags: tags ?? this.tags,
      savedAt: savedAt ?? this.savedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastMovedAt: lastMovedAt ?? this.lastMovedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      warrantyEndDate: clearWarrantyEndDate
          ? null
          : (warrantyEndDate ?? this.warrantyEndDate),
      isArchived: isArchived ?? this.isArchived,
      notes: clearNotes ? null : (notes ?? this.notes),
      invoicePath: clearInvoicePath ? null : (invoicePath ?? this.invoicePath),
      invoiceFileName: clearInvoiceFileName
          ? null
          : (invoiceFileName ?? this.invoiceFileName),
      invoiceFileSizeBytes: clearInvoiceFileSizeBytes
          ? null
          : (invoiceFileSizeBytes ?? this.invoiceFileSizeBytes),
      cloudId: clearCloudId ? null : (cloudId ?? this.cloudId),
      lastSyncedAt:
          clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
      isBackedUp: isBackedUp ?? this.isBackedUp,
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
      areaName: areaName ?? this.areaName,
      roomName: roomName ?? this.roomName,
      zoneName: zoneName ?? this.zoneName,
    );
  }

  /// Converts to a map for SQLite insertion. Does NOT include joined fields.
  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'name': name,
      // Legacy location column — kept during Phase-5 migration window.
      'location_uuid': locationUuid,
      // New hierarchical FK columns added in DB v13.
      'area_uuid': areaUuid,
      'room_uuid': roomUuid,
      'zone_uuid': zoneUuid,
      'image_paths': jsonEncode(imagePaths),
      'tags': jsonEncode(tags),
      'saved_at': savedAt.millisecondsSinceEpoch,
      'updated_at': updatedAt?.millisecondsSinceEpoch,
      'last_updated_at': lastUpdatedAt?.millisecondsSinceEpoch,
      'last_moved_at': lastMovedAt?.millisecondsSinceEpoch,
      'latitude': latitude,
      'longitude': longitude,
      'expiry_date': expiryDate?.millisecondsSinceEpoch,
      'warranty_end_date': warrantyEndDate?.millisecondsSinceEpoch,
      'is_archived': isArchived ? 1 : 0,
      'notes': notes,
      'invoice_path': invoicePath,
      'invoice_file_name': invoiceFileName,
      'invoice_file_size_bytes': invoiceFileSizeBytes,
      'cloud_id': cloudId,
      'last_synced_at': lastSyncedAt?.millisecondsSinceEpoch,
      'is_backed_up': isBackedUp ? 1 : 0,
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
      lastUpdatedAt: map['last_updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_updated_at'] as int)
          : (map['updated_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
              : null),
      lastMovedAt: map['last_moved_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_moved_at'] as int)
          : null,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      expiryDate: map['expiry_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expiry_date'] as int)
          : null,
      warrantyEndDate: map['warranty_end_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              map['warranty_end_date'] as int,
            )
          : null,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      notes: map['notes'] as String?,
      invoicePath: map['invoice_path'] as String?,
      invoiceFileName: map['invoice_file_name'] as String?,
      invoiceFileSizeBytes: map['invoice_file_size_bytes'] as int?,
      cloudId: map['cloud_id'] as String?,
      lastSyncedAt: map['last_synced_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_synced_at'] as int)
          : null,
      isBackedUp: (map['is_backed_up'] as int? ?? 0) == 1,
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
      visibility: ItemVisibility.fromString(map['visibility'] as String?),
      householdId:
          map['household_id'] as String? ?? map['householdId'] as String?,
      sharedWithMemberUuids: List<String>.from(
        jsonDecode(
          map['shared_with_member_uuids'] as String? ??
              map['sharedWithMemberUuids'] as String? ??
              '[]',
        ) as List,
      ),
      // New hierarchical FK columns (null on pre-migration rows — that's fine).
      areaUuid: map['area_uuid'] as String?,
      roomUuid: map['room_uuid'] as String?,
      zoneUuid: map['zone_uuid'] as String?,
      // Joined display fields from DAO queries — never stored in the items row.
      locationName: map['location_name'] as String?,
      locationFullPath: map['location_full_path'] as String?,
      areaName: map['area_name'] as String?,
      roomName: map['room_name'] as String?,
      zoneName: map['zone_name'] as String?,
    );
  }

  /// Converts to JSON for cloud sync. Excludes joined display fields.
  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'locationUuid': locationUuid,
      // Hierarchical location FKs — needed to restore zone/room/area links
      // without relying solely on the migration service at startup.
      'areaUuid': areaUuid,
      'roomUuid': roomUuid,
      'zoneUuid': zoneUuid,
      'imagePaths': imagePaths,
      'tags': tags,
      'savedAt': savedAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
      'lastMovedAt': lastMovedAt?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'expiryDate': expiryDate?.toIso8601String(),
      'warrantyEndDate': warrantyEndDate?.toIso8601String(),
      'isArchived': isArchived,
      'notes': notes,
      'invoicePath': invoicePath,
      'invoiceFileName': invoiceFileName,
      'invoiceFileSizeBytes': invoiceFileSizeBytes,
      'cloudId': cloudId,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'isBackedUp': isBackedUp,
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
      lastUpdatedAt:
          _dateTimeFromJson(json['lastUpdatedAt']) ??
          _dateTimeFromJson(json['updatedAt']),
      lastMovedAt: _dateTimeFromJson(json['lastMovedAt']),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      expiryDate: _dateTimeFromJson(json['expiryDate']),
      warrantyEndDate: _dateTimeFromJson(json['warrantyEndDate']),
      isArchived: json['isArchived'] as bool? ?? false,
      notes: json['notes'] as String?,
      invoicePath: json['invoicePath'] as String?,
      invoiceFileName: json['invoiceFileName'] as String?,
      invoiceFileSizeBytes: (json['invoiceFileSizeBytes'] as num?)?.toInt(),
      cloudId: json['cloudId'] as String?,
      lastSyncedAt: _dateTimeFromJson(json['lastSyncedAt']),
      isBackedUp: json['isBackedUp'] as bool? ?? false,
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
