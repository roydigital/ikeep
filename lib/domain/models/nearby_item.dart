import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an item publicly listed for lending in a locality.
/// Lives in Firestore at: nearby_items/{itemUuid}
///
/// Similar to [SharedItem] but includes a locality field for geo-based
/// discovery among strangers in the same neighborhood.
class NearbyItem {
  const NearbyItem({
    required this.itemUuid,
    required this.ownerUid,
    required this.ownerName,
    required this.name,
    required this.locality,
    this.country = '',
    this.locationName = '',
    this.tags = const [],
    this.isLent = false,
    this.lentToName,
    this.lentToUid,
    this.expectedReturnDate,
    this.createdAt,
    this.updatedAt,
  });

  final String itemUuid;
  final String ownerUid;
  final String ownerName;
  final String name;
  final String locality;
  final String country;
  final String locationName;
  final List<String> tags;
  final bool isLent;
  final String? lentToName;
  final String? lentToUid;
  final DateTime? expectedReturnDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether this item is available to borrow (not currently lent out).
  bool get isAvailable => !isLent;

  /// Constructs from a Firestore document snapshot.
  factory NearbyItem.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return NearbyItem(
      itemUuid: doc.id,
      ownerUid: d['ownerUid'] as String? ?? '',
      ownerName: d['ownerName'] as String? ?? 'Unknown',
      name: d['name'] as String? ?? '',
      locality: d['locality'] as String? ?? '',
      country: d['country'] as String? ?? '',
      locationName: d['locationName'] as String? ?? '',
      tags: List<String>.from(d['tags'] as List? ?? []),
      isLent: (d['isLent'] as bool?) ?? false,
      lentToName: d['lentToName'] as String?,
      lentToUid: d['lentToUid'] as String?,
      expectedReturnDate: _parseTimestamp(d['expectedReturnDate']),
      createdAt: _parseTimestamp(d['createdAt']),
      updatedAt: _parseTimestamp(d['updatedAt']),
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
      (other is NearbyItem && other.itemUuid == itemUuid);

  @override
  int get hashCode => itemUuid.hashCode;

  @override
  String toString() =>
      'NearbyItem(uuid: $itemUuid, name: $name, locality: $locality)';
}
