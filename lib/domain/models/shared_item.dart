import 'package:cloud_firestore/cloud_firestore.dart';

/// Lightweight representation of an item shared in the household catalog.
/// Lives in Firestore at: households/{id}/shared_items/{itemUuid}
///
/// This is NOT a full Item — it contains only the metadata needed for
/// household members to browse and request items from each other.
class SharedItem {
  const SharedItem({
    required this.itemUuid,
    required this.ownerUid,
    required this.ownerName,
    required this.name,
    this.locationName = '',
    this.tags = const [],
    this.isLent = false,
    this.lentToName,
    this.lentToUid,
    this.expectedReturnDate,
    this.updatedAt,
  });

  final String itemUuid;
  final String ownerUid;
  final String ownerName;
  final String name;
  final String locationName;
  final List<String> tags;
  final bool isLent;
  final String? lentToName;
  final String? lentToUid;
  final DateTime? expectedReturnDate;
  final DateTime? updatedAt;

  /// Constructs a SharedItem from a Firestore document snapshot.
  factory SharedItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;

    final returnDate = d['expectedReturnDate'];
    DateTime? parsedReturnDate;
    if (returnDate is Timestamp) {
      parsedReturnDate = returnDate.toDate();
    }

    final updated = d['updatedAt'];
    DateTime? parsedUpdated;
    if (updated is Timestamp) {
      parsedUpdated = updated.toDate();
    }

    return SharedItem(
      itemUuid: doc.id,
      ownerUid: d['ownerUid'] as String? ?? '',
      ownerName: d['ownerName'] as String? ?? 'Unknown',
      name: d['name'] as String? ?? '',
      locationName: d['locationName'] as String? ?? '',
      tags: List<String>.from(d['tags'] as List? ?? []),
      isLent: (d['isLent'] as bool?) ?? false,
      lentToName: d['lentToName'] as String?,
      lentToUid: d['lentToUid'] as String?,
      expectedReturnDate: parsedReturnDate,
      updatedAt: parsedUpdated,
    );
  }

  /// Whether this item is available to request (not lent out).
  bool get isAvailable => !isLent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SharedItem && other.itemUuid == itemUuid);

  @override
  int get hashCode => itemUuid.hashCode;

  @override
  String toString() =>
      'SharedItem(uuid: $itemUuid, name: $name, owner: $ownerName)';
}
