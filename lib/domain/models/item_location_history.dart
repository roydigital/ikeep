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
  });

  final String uuid;
  final String itemUuid;
  final String? locationUuid;
  final String? movedByMemberUuid;
  final String? movedByName;

  /// Snapshot of the location name at the time of the move.
  /// Stored separately so renames don't break history display.
  final String locationName;
  final DateTime movedAt;
  final String? note;

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
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemLocationHistory && other.uuid == uuid);

  @override
  int get hashCode => uuid.hashCode;
}
