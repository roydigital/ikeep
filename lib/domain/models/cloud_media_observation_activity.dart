import '../../core/constants/db_constants.dart';
import 'media_cache_entry.dart';

class CloudMediaObservationActivity {
  const CloudMediaObservationActivity({
    required this.activityKey,
    required this.mediaType,
    required this.storagePath,
    this.version,
    this.contentHash,
    required this.downloadCount,
    required this.totalDownloadedBytes,
    required this.lastDownloadedBytes,
    required this.createdAt,
    required this.lastDownloadedAt,
    required this.updatedAt,
  });

  final String activityKey;
  final CachedMediaType mediaType;
  final String storagePath;
  final int? version;
  final String? contentHash;
  final int downloadCount;
  final int totalDownloadedBytes;
  final int lastDownloadedBytes;
  final DateTime createdAt;
  final DateTime lastDownloadedAt;
  final DateTime updatedAt;

  factory CloudMediaObservationActivity.initial({
    required String activityKey,
    required CachedMediaType mediaType,
    required String storagePath,
    int? version,
    String? contentHash,
    required DateTime now,
  }) {
    return CloudMediaObservationActivity(
      activityKey: activityKey,
      mediaType: mediaType,
      storagePath: storagePath,
      version: version,
      contentHash: contentHash,
      downloadCount: 0,
      totalDownloadedBytes: 0,
      lastDownloadedBytes: 0,
      createdAt: now,
      lastDownloadedAt: now,
      updatedAt: now,
    );
  }

  CloudMediaObservationActivity copyWith({
    String? activityKey,
    CachedMediaType? mediaType,
    String? storagePath,
    int? version,
    String? contentHash,
    int? downloadCount,
    int? totalDownloadedBytes,
    int? lastDownloadedBytes,
    DateTime? createdAt,
    DateTime? lastDownloadedAt,
    DateTime? updatedAt,
    bool clearVersion = false,
    bool clearContentHash = false,
  }) {
    return CloudMediaObservationActivity(
      activityKey: activityKey ?? this.activityKey,
      mediaType: mediaType ?? this.mediaType,
      storagePath: storagePath ?? this.storagePath,
      version: clearVersion ? null : (version ?? this.version),
      contentHash:
          clearContentHash ? null : (contentHash ?? this.contentHash),
      downloadCount: downloadCount ?? this.downloadCount,
      totalDownloadedBytes:
          totalDownloadedBytes ?? this.totalDownloadedBytes,
      lastDownloadedBytes: lastDownloadedBytes ?? this.lastDownloadedBytes,
      createdAt: createdAt ?? this.createdAt,
      lastDownloadedAt: lastDownloadedAt ?? this.lastDownloadedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      DbConstants.colCloudMediaObservationKey: activityKey,
      DbConstants.colCloudMediaObservationType: mediaType.dbValue,
      DbConstants.colCloudMediaObservationStoragePath: storagePath,
      DbConstants.colCloudMediaObservationVersion: version,
      DbConstants.colCloudMediaObservationContentHash: contentHash,
      DbConstants.colCloudMediaObservationDownloadCount: downloadCount,
      DbConstants.colCloudMediaObservationTotalDownloadedBytes:
          totalDownloadedBytes,
      DbConstants.colCloudMediaObservationLastDownloadedBytes:
          lastDownloadedBytes,
      DbConstants.colCloudMediaObservationCreatedAt:
          createdAt.millisecondsSinceEpoch,
      DbConstants.colCloudMediaObservationLastDownloadedAt:
          lastDownloadedAt.millisecondsSinceEpoch,
      DbConstants.colCloudMediaObservationUpdatedAt:
          updatedAt.millisecondsSinceEpoch,
    };
  }

  factory CloudMediaObservationActivity.fromMap(Map<String, Object?> map) {
    DateTime parseDate(String key) {
      return DateTime.fromMillisecondsSinceEpoch(
        (map[key] as num?)?.toInt() ?? 0,
      );
    }

    return CloudMediaObservationActivity(
      activityKey: map[DbConstants.colCloudMediaObservationKey] as String? ?? '',
      mediaType: CachedMediaType.fromDbValue(
        map[DbConstants.colCloudMediaObservationType] as String? ?? '',
      ),
      storagePath:
          map[DbConstants.colCloudMediaObservationStoragePath] as String? ?? '',
      version:
          (map[DbConstants.colCloudMediaObservationVersion] as num?)?.toInt(),
      contentHash: map[DbConstants.colCloudMediaObservationContentHash]
          as String?,
      downloadCount:
          (map[DbConstants.colCloudMediaObservationDownloadCount] as num?)
                  ?.toInt() ??
              0,
      totalDownloadedBytes:
          (map[DbConstants.colCloudMediaObservationTotalDownloadedBytes]
                      as num?)
                  ?.toInt() ??
              0,
      lastDownloadedBytes:
          (map[DbConstants.colCloudMediaObservationLastDownloadedBytes]
                      as num?)
                  ?.toInt() ??
              0,
      createdAt: parseDate(DbConstants.colCloudMediaObservationCreatedAt),
      lastDownloadedAt:
          parseDate(DbConstants.colCloudMediaObservationLastDownloadedAt),
      updatedAt: parseDate(DbConstants.colCloudMediaObservationUpdatedAt),
    );
  }
}
