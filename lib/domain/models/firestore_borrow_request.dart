import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a borrow request in Firestore.
enum FirestoreBorrowStatus {
  pending('pending'),
  approved('approved'),
  denied('denied'),
  cancelled('cancelled'),
  returned('returned');

  const FirestoreBorrowStatus(this.value);
  final String value;

  static FirestoreBorrowStatus fromString(String? s) {
    return FirestoreBorrowStatus.values.firstWhere(
      (e) => e.value == s,
      orElse: () => FirestoreBorrowStatus.pending,
    );
  }
}

/// Represents a borrow request stored in Firestore.
/// Path: households/{id}/borrow_requests/{requestId}
///
/// This is the cross-device borrow request — it lives in Firestore so
/// both the item owner and requester can see and act on it from their
/// own devices.
class FirestoreBorrowRequest {
  const FirestoreBorrowRequest({
    required this.id,
    required this.itemUuid,
    required this.itemName,
    required this.ownerUid,
    required this.ownerName,
    required this.requesterUid,
    required this.requesterName,
    required this.status,
    required this.requestedAt,
    this.respondedAt,
    this.requestedReturnDate,
    this.note,
    this.source = 'household',
  });

  final String id;
  final String itemUuid;
  final String itemName;
  final String ownerUid;
  final String ownerName;
  final String requesterUid;
  final String requesterName;
  final FirestoreBorrowStatus status;
  final DateTime requestedAt;
  final DateTime? respondedAt;
  final DateTime? requestedReturnDate;
  final String? note;
  final String source;

  bool get isPending => status == FirestoreBorrowStatus.pending;
  bool get isApproved => status == FirestoreBorrowStatus.approved;
  bool get isNearby => source == 'nearby';

  /// Constructs from a Firestore document map (must include 'id' key).
  factory FirestoreBorrowRequest.fromMap(Map<String, dynamic> data) {
    return FirestoreBorrowRequest(
      id: data['id'] as String? ?? '',
      itemUuid: data['itemUuid'] as String? ?? '',
      itemName: data['itemName'] as String? ?? '',
      ownerUid: data['ownerUid'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? '',
      requesterUid: data['requesterUid'] as String? ?? '',
      requesterName: data['requesterName'] as String? ?? '',
      status: FirestoreBorrowStatus.fromString(data['status'] as String?),
      requestedAt: _parseTimestamp(data['requestedAt']) ?? DateTime.now(),
      respondedAt: _parseTimestamp(data['respondedAt']),
      requestedReturnDate: _parseTimestamp(data['requestedReturnDate']),
      note: data['note'] as String?,
      source: data['source'] as String? ?? 'household',
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FirestoreBorrowRequest && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
