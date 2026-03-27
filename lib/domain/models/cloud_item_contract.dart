import 'item.dart';
import 'cloud_media_descriptor.dart';

/// Transitional Firestore contract for cloud-backed items.
///
/// The current app continues to write and read the legacy item JSON fields so
/// existing backup, restore, and UI flows remain unchanged. This contract adds
/// the new metadata-only fields required for later optimization phases.
class CloudItemContract {
  const CloudItemContract({
    required this.itemId,
    required this.ownerUid,
    this.householdId,
    required this.visibility,
    required this.title,
    this.note,
    this.areaUuid,
    this.roomUuid,
    this.zoneUuid,
    required this.createdAt,
    required this.updatedAt,
    this.lastMovedAt,
    required this.lastContentUpdatedAt,
    required this.syncVersion,
    required this.isBackedUp,
    this.imageMedia = const [],
    this.invoiceMedia,
  });

  final String itemId;
  final String ownerUid;
  final String? householdId;
  final String visibility;
  final String title;
  final String? note;
  final String? areaUuid;
  final String? roomUuid;
  final String? zoneUuid;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMovedAt;
  final DateTime lastContentUpdatedAt;
  final int syncVersion;
  final bool isBackedUp;
  final List<CloudMediaDescriptor> imageMedia;
  final CloudMediaDescriptor? invoiceMedia;

  factory CloudItemContract.fromItem({
    required Item item,
    required String ownerUid,
    List<CloudMediaDescriptor> imageMedia = const [],
    CloudMediaDescriptor? invoiceMedia,
  }) {
    final resolvedUpdatedAt = item.updatedAt ?? item.savedAt;
    final resolvedLastContentUpdatedAt =
        item.lastUpdatedAt ?? item.updatedAt ?? item.savedAt;

    return CloudItemContract(
      itemId: item.uuid,
      ownerUid: ownerUid,
      householdId: item.householdId,
      visibility: item.visibility.value,
      title: item.name,
      note: item.notes,
      areaUuid: item.areaUuid,
      roomUuid: item.roomUuid,
      zoneUuid: item.zoneUuid,
      createdAt: item.savedAt,
      updatedAt: resolvedUpdatedAt,
      lastMovedAt: item.lastMovedAt,
      lastContentUpdatedAt: resolvedLastContentUpdatedAt,
      syncVersion: resolvedLastContentUpdatedAt.millisecondsSinceEpoch
          .clamp(1, 1 << 62)
          .toInt(),
      isBackedUp: item.isBackedUp,
      imageMedia: imageMedia,
      invoiceMedia: invoiceMedia,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'itemId': itemId,
      'ownerUid': ownerUid,
      'householdId': householdId,
      'visibility': visibility,
      'title': title,
      'note': note,
      'areaUuid': areaUuid,
      'roomUuid': roomUuid,
      'zoneUuid': zoneUuid,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'lastMovedAt': lastMovedAt?.toUtc().toIso8601String(),
      'lastContentUpdatedAt': lastContentUpdatedAt.toUtc().toIso8601String(),
      'syncVersion': syncVersion,
      'isBackedUp': isBackedUp,
      'imageMedia': imageMedia.map((entry) => entry.toJson()).toList(),
      'invoiceMedia': invoiceMedia?.toJson(),
    };
  }
}
