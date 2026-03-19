class ItemLocationHistory {
  const ItemLocationHistory({
    required this.uuid,
    required this.itemUuid,
    required this.locationName,
    required this.movedAt,
    this.locationUuid,
    this.movedByMemberUuid,
    this.movedByName,
    this.note,
    this.householdId,
    this.userEmail,
    this.actionDescription,
  });

  final String uuid;
  final String itemUuid;
  final String? locationUuid;
  final String? movedByMemberUuid;
  final String? movedByName;
  final String? householdId;
  final String? userEmail;

  /// Snapshot of the location name at the time of the move.
  /// Stored separately so renames don't break history display.
  final String locationName;
  final DateTime movedAt;
  final String? note;
  final String? actionDescription;

  String get historyId => uuid;
  String get itemId => itemUuid;
  String? get userId => movedByMemberUuid;
  String? get userName => movedByName;
  DateTime get timestamp => movedAt;
  String get resolvedActionDescription =>
      actionDescription ?? note ?? 'Moved to $locationName';

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'item_uuid': itemUuid,
      'location_uuid': locationUuid,
      'location_name': locationName,
      'moved_at': movedAt.millisecondsSinceEpoch,
      'moved_by_member_uuid': movedByMemberUuid,
      'moved_by_name': movedByName,
      'note': note,
      'household_id': householdId,
      'user_email': userEmail,
      'action_description': resolvedActionDescription,
    };
  }

  factory ItemLocationHistory.fromMap(Map<String, dynamic> map) {
    return ItemLocationHistory(
      uuid: map['uuid'] as String,
      itemUuid: map['item_uuid'] as String,
      locationUuid: map['location_uuid'] as String?,
      locationName: map['location_name'] as String,
      movedAt: DateTime.fromMillisecondsSinceEpoch(map['moved_at'] as int),
      movedByMemberUuid: map['moved_by_member_uuid'] as String?,
      movedByName: map['moved_by_name'] as String?,
      note: map['note'] as String?,
      householdId:
          map['household_id'] as String? ?? map['householdId'] as String?,
      userEmail: map['user_email'] as String? ?? map['userEmail'] as String?,
      actionDescription: map['action_description'] as String? ??
          map['actionDescription'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'historyId': historyId,
      'itemId': itemId,
      'householdId': householdId,
      'locationUuid': locationUuid,
      'locationName': locationName,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'timestamp': timestamp.toIso8601String(),
      'actionDescription': resolvedActionDescription,
    };
  }

  factory ItemLocationHistory.fromJson(Map<String, dynamic> json) {
    return ItemLocationHistory(
      uuid: json['historyId'] as String? ?? json['uuid'] as String,
      itemUuid: json['itemId'] as String? ?? json['itemUuid'] as String,
      locationUuid: json['locationUuid'] as String?,
      locationName: json['locationName'] as String? ??
          _inferLocationName(json['actionDescription'] as String?),
      movedAt: DateTime.parse(
        json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
      ),
      movedByMemberUuid: json['userId'] as String?,
      movedByName: json['userName'] as String?,
      note: json['note'] as String?,
      householdId: json['householdId'] as String?,
      userEmail: json['userEmail'] as String?,
      actionDescription: json['actionDescription'] as String?,
    );
  }

  static String _inferLocationName(String? actionDescription) {
    if (actionDescription == null || actionDescription.trim().isEmpty) {
      return 'Unknown';
    }
    const prefix = 'Moved to ';
    if (actionDescription.startsWith(prefix)) {
      return actionDescription.substring(prefix.length).trim();
    }
    return actionDescription;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemLocationHistory && other.uuid == uuid);

  @override
  int get hashCode => uuid.hashCode;
}
