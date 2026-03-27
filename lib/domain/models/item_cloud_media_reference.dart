import '../../core/constants/db_constants.dart';
import 'cloud_media_descriptor.dart';

enum ItemCloudMediaRole {
  image('image'),
  invoice('invoice');

  const ItemCloudMediaRole(this.dbValue);

  final String dbValue;

  static ItemCloudMediaRole fromDbValue(String value) {
    return ItemCloudMediaRole.values.firstWhere(
      (role) => role.dbValue == value,
      orElse: () => ItemCloudMediaRole.image,
    );
  }
}

/// Local SQLite sidecar row that keeps restored/shared cloud media metadata
/// available without forcing the main [Item] schema to change.
class ItemCloudMediaReference {
  const ItemCloudMediaReference({
    required this.itemUuid,
    required this.mediaRole,
    required this.slotIndex,
    required this.storagePath,
    this.thumbnailPath,
    required this.mimeType,
    this.byteSize,
    this.contentHash,
    this.version,
    required this.updatedAt,
  });

  final String itemUuid;
  final ItemCloudMediaRole mediaRole;
  final int slotIndex;
  final String storagePath;
  final String? thumbnailPath;
  final String mimeType;
  final int? byteSize;
  final String? contentHash;
  final int? version;
  final DateTime updatedAt;

  CloudMediaDescriptor toDescriptor() {
    return CloudMediaDescriptor(
      storagePath: storagePath,
      thumbnailPath: thumbnailPath,
      mimeType: mimeType,
      byteSize: byteSize ?? 0,
      contentHash: contentHash,
      version: version ?? updatedAt.millisecondsSinceEpoch,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      DbConstants.colItemCloudMediaItemUuid: itemUuid,
      DbConstants.colItemCloudMediaRole: mediaRole.dbValue,
      DbConstants.colItemCloudMediaSlotIndex: slotIndex,
      DbConstants.colItemCloudMediaStoragePath: storagePath,
      DbConstants.colItemCloudMediaThumbnailPath: thumbnailPath,
      DbConstants.colItemCloudMediaMimeType: mimeType,
      DbConstants.colItemCloudMediaByteSize: byteSize,
      DbConstants.colItemCloudMediaContentHash: contentHash,
      DbConstants.colItemCloudMediaVersion: version,
      DbConstants.colItemCloudMediaUpdatedAt:
          updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ItemCloudMediaReference.fromMap(Map<String, Object?> map) {
    return ItemCloudMediaReference(
      itemUuid: map[DbConstants.colItemCloudMediaItemUuid] as String? ?? '',
      mediaRole: ItemCloudMediaRole.fromDbValue(
        map[DbConstants.colItemCloudMediaRole] as String? ?? '',
      ),
      slotIndex:
          (map[DbConstants.colItemCloudMediaSlotIndex] as num?)?.toInt() ?? 0,
      storagePath:
          map[DbConstants.colItemCloudMediaStoragePath] as String? ?? '',
      thumbnailPath:
          map[DbConstants.colItemCloudMediaThumbnailPath] as String?,
      mimeType: map[DbConstants.colItemCloudMediaMimeType] as String? ??
          'application/octet-stream',
      byteSize: (map[DbConstants.colItemCloudMediaByteSize] as num?)?.toInt(),
      contentHash: map[DbConstants.colItemCloudMediaContentHash] as String?,
      version: (map[DbConstants.colItemCloudMediaVersion] as num?)?.toInt(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map[DbConstants.colItemCloudMediaUpdatedAt] as num?)?.toInt() ?? 0,
      ),
    );
  }

  ItemCloudMediaReference copyWith({
    String? itemUuid,
    ItemCloudMediaRole? mediaRole,
    int? slotIndex,
    String? storagePath,
    String? thumbnailPath,
    String? mimeType,
    int? byteSize,
    String? contentHash,
    int? version,
    DateTime? updatedAt,
    bool clearThumbnailPath = false,
    bool clearByteSize = false,
    bool clearContentHash = false,
    bool clearVersion = false,
  }) {
    return ItemCloudMediaReference(
      itemUuid: itemUuid ?? this.itemUuid,
      mediaRole: mediaRole ?? this.mediaRole,
      slotIndex: slotIndex ?? this.slotIndex,
      storagePath: storagePath ?? this.storagePath,
      thumbnailPath: clearThumbnailPath
          ? null
          : (thumbnailPath ?? this.thumbnailPath),
      mimeType: mimeType ?? this.mimeType,
      byteSize: clearByteSize ? null : (byteSize ?? this.byteSize),
      contentHash:
          clearContentHash ? null : (contentHash ?? this.contentHash),
      version: clearVersion ? null : (version ?? this.version),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
