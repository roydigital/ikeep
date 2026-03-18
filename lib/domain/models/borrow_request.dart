import 'dart:convert';

enum BorrowRequestStatus { pending, approved, denied, cancelled }

extension BorrowRequestStatusX on BorrowRequestStatus {
  String get value {
    switch (this) {
      case BorrowRequestStatus.pending:
        return 'pending';
      case BorrowRequestStatus.approved:
        return 'approved';
      case BorrowRequestStatus.denied:
        return 'denied';
      case BorrowRequestStatus.cancelled:
        return 'cancelled';
    }
  }

  static BorrowRequestStatus fromValue(String? value) {
    switch (value) {
      case 'approved':
        return BorrowRequestStatus.approved;
      case 'denied':
        return BorrowRequestStatus.denied;
      case 'cancelled':
        return BorrowRequestStatus.cancelled;
      case 'pending':
      default:
        return BorrowRequestStatus.pending;
    }
  }
}

class BorrowRequest {
  const BorrowRequest({
    required this.uuid,
    required this.itemUuid,
    required this.ownerMemberUuid,
    required this.ownerMemberName,
    required this.requesterMemberUuid,
    required this.requesterMemberName,
    required this.status,
    required this.requestedAt,
    this.respondedAt,
    this.requestedReturnDate,
    this.note,
    this.itemName,
    this.itemImagePaths = const [],
    this.itemIsLent = false,
    this.itemIsAvailableForLending = false,
  });

  final String uuid;
  final String itemUuid;
  final String ownerMemberUuid;
  final String ownerMemberName;
  final String requesterMemberUuid;
  final String requesterMemberName;
  final BorrowRequestStatus status;
  final DateTime requestedAt;
  final DateTime? respondedAt;
  final DateTime? requestedReturnDate;
  final String? note;

  // Joined item display fields.
  final String? itemName;
  final List<String> itemImagePaths;
  final bool itemIsLent;
  final bool itemIsAvailableForLending;

  bool get isPending => status == BorrowRequestStatus.pending;

  BorrowRequest copyWith({
    String? uuid,
    String? itemUuid,
    String? ownerMemberUuid,
    String? ownerMemberName,
    String? requesterMemberUuid,
    String? requesterMemberName,
    BorrowRequestStatus? status,
    DateTime? requestedAt,
    DateTime? respondedAt,
    DateTime? requestedReturnDate,
    String? note,
    String? itemName,
    List<String>? itemImagePaths,
    bool? itemIsLent,
    bool? itemIsAvailableForLending,
    bool clearRespondedAt = false,
    bool clearRequestedReturnDate = false,
    bool clearNote = false,
  }) {
    return BorrowRequest(
      uuid: uuid ?? this.uuid,
      itemUuid: itemUuid ?? this.itemUuid,
      ownerMemberUuid: ownerMemberUuid ?? this.ownerMemberUuid,
      ownerMemberName: ownerMemberName ?? this.ownerMemberName,
      requesterMemberUuid: requesterMemberUuid ?? this.requesterMemberUuid,
      requesterMemberName: requesterMemberName ?? this.requesterMemberName,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      respondedAt: clearRespondedAt ? null : (respondedAt ?? this.respondedAt),
      requestedReturnDate: clearRequestedReturnDate
          ? null
          : (requestedReturnDate ?? this.requestedReturnDate),
      note: clearNote ? null : (note ?? this.note),
      itemName: itemName ?? this.itemName,
      itemImagePaths: itemImagePaths ?? this.itemImagePaths,
      itemIsLent: itemIsLent ?? this.itemIsLent,
      itemIsAvailableForLending:
          itemIsAvailableForLending ?? this.itemIsAvailableForLending,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'item_uuid': itemUuid,
      'owner_member_uuid': ownerMemberUuid,
      'owner_member_name': ownerMemberName,
      'requester_member_uuid': requesterMemberUuid,
      'requester_member_name': requesterMemberName,
      'status': status.value,
      'requested_at': requestedAt.millisecondsSinceEpoch,
      'responded_at': respondedAt?.millisecondsSinceEpoch,
      'requested_return_date': requestedReturnDate?.millisecondsSinceEpoch,
      'note': note,
    };
  }

  factory BorrowRequest.fromMap(Map<String, dynamic> map) {
    return BorrowRequest(
      uuid: map['uuid'] as String,
      itemUuid: map['item_uuid'] as String,
      ownerMemberUuid: map['owner_member_uuid'] as String,
      ownerMemberName: map['owner_member_name'] as String,
      requesterMemberUuid: map['requester_member_uuid'] as String,
      requesterMemberName: map['requester_member_name'] as String,
      status: BorrowRequestStatusX.fromValue(map['status'] as String?),
      requestedAt:
          DateTime.fromMillisecondsSinceEpoch(map['requested_at'] as int),
      respondedAt: map['responded_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['responded_at'] as int),
      requestedReturnDate: map['requested_return_date'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map['requested_return_date'] as int,
            ),
      note: map['note'] as String?,
      itemName: map['item_name'] as String?,
      itemImagePaths: List<String>.from(
        jsonDecode(map['item_image_paths'] as String? ?? '[]') as List,
      ),
      itemIsLent: (map['item_is_lent'] as int? ?? 0) == 1,
      itemIsAvailableForLending:
          (map['item_is_available_for_lending'] as int? ?? 0) == 1,
    );
  }
}
