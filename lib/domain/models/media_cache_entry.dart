import '../../core/constants/db_constants.dart';

enum CachedMediaType {
  thumbnail('thumbnail'),
  fullImage('full_image'),
  pdf('pdf');

  const CachedMediaType(this.dbValue);

  final String dbValue;

  static CachedMediaType fromDbValue(String value) {
    return CachedMediaType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => CachedMediaType.fullImage,
    );
  }
}

/// Persistent registry row for a locally cached cloud media file.
class MediaCacheEntry {
  const MediaCacheEntry({
    required this.cacheKey,
    required this.mediaType,
    required this.storagePath,
    this.version,
    this.contentHash,
    required this.localFilePath,
    required this.mimeType,
    this.byteSize,
    required this.createdAt,
    required this.lastAccessedAt,
  });

  final String cacheKey;
  final CachedMediaType mediaType;
  final String storagePath;
  final int? version;
  final String? contentHash;
  final String localFilePath;
  final String mimeType;
  final int? byteSize;
  final DateTime createdAt;
  final DateTime lastAccessedAt;

  Map<String, Object?> toMap() {
    return {
      DbConstants.colMediaCacheKey: cacheKey,
      DbConstants.colMediaCacheType: mediaType.dbValue,
      DbConstants.colMediaStoragePath: storagePath,
      DbConstants.colMediaVersion: version,
      DbConstants.colMediaContentHash: contentHash,
      DbConstants.colMediaLocalFilePath: localFilePath,
      DbConstants.colMediaMimeType: mimeType,
      DbConstants.colMediaByteSize: byteSize,
      DbConstants.colMediaCreatedAt: createdAt.millisecondsSinceEpoch,
      DbConstants.colMediaLastAccessedAt:
          lastAccessedAt.millisecondsSinceEpoch,
    };
  }

  factory MediaCacheEntry.fromMap(Map<String, Object?> map) {
    return MediaCacheEntry(
      cacheKey: map[DbConstants.colMediaCacheKey] as String? ?? '',
      mediaType: CachedMediaType.fromDbValue(
        map[DbConstants.colMediaCacheType] as String? ?? '',
      ),
      storagePath: map[DbConstants.colMediaStoragePath] as String? ?? '',
      version: (map[DbConstants.colMediaVersion] as num?)?.toInt(),
      contentHash: map[DbConstants.colMediaContentHash] as String?,
      localFilePath: map[DbConstants.colMediaLocalFilePath] as String? ?? '',
      mimeType: map[DbConstants.colMediaMimeType] as String? ??
          'application/octet-stream',
      byteSize: (map[DbConstants.colMediaByteSize] as num?)?.toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map[DbConstants.colMediaCreatedAt] as num?)?.toInt() ?? 0,
      ),
      lastAccessedAt: DateTime.fromMillisecondsSinceEpoch(
        (map[DbConstants.colMediaLastAccessedAt] as num?)?.toInt() ?? 0,
      ),
    );
  }

  MediaCacheEntry copyWith({
    String? cacheKey,
    CachedMediaType? mediaType,
    String? storagePath,
    int? version,
    String? contentHash,
    String? localFilePath,
    String? mimeType,
    int? byteSize,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    bool clearVersion = false,
    bool clearContentHash = false,
    bool clearByteSize = false,
  }) {
    return MediaCacheEntry(
      cacheKey: cacheKey ?? this.cacheKey,
      mediaType: mediaType ?? this.mediaType,
      storagePath: storagePath ?? this.storagePath,
      version: clearVersion ? null : (version ?? this.version),
      contentHash:
          clearContentHash ? null : (contentHash ?? this.contentHash),
      localFilePath: localFilePath ?? this.localFilePath,
      mimeType: mimeType ?? this.mimeType,
      byteSize: clearByteSize ? null : (byteSize ?? this.byteSize),
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }
}
