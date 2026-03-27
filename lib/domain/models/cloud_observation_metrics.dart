import '../../core/constants/db_constants.dart';
import 'cloud_entitlement.dart';

class CloudObservationMetrics {
  const CloudObservationMetrics({
    required this.scope,
    required this.planMode,
    required this.restoreCount,
    required this.restoreBurstCount,
    required this.fullMediaHydrationCount,
    required this.metadataOnlyRestoreCount,
    required this.thumbnailDownloadCount,
    required this.fullImageDownloadCount,
    required this.pdfDownloadCount,
    required this.estimatedDownloadBytes,
    required this.estimatedUploadBytes,
    required this.repeatedSyncCount,
    this.lastRestoreAt,
    this.lastHeavyDownloadAt,
    this.lastSyncAt,
    required this.updatedAt,
  });

  final String scope;
  final CloudEntitlementMode planMode;
  final int restoreCount;
  final int restoreBurstCount;
  final int fullMediaHydrationCount;
  final int metadataOnlyRestoreCount;
  final int thumbnailDownloadCount;
  final int fullImageDownloadCount;
  final int pdfDownloadCount;
  final int estimatedDownloadBytes;
  final int estimatedUploadBytes;
  final int repeatedSyncCount;
  final DateTime? lastRestoreAt;
  final DateTime? lastHeavyDownloadAt;
  final DateTime? lastSyncAt;
  final DateTime updatedAt;

  factory CloudObservationMetrics.initial({
    required String scope,
    required CloudEntitlementMode planMode,
  }) {
    return CloudObservationMetrics(
      scope: scope,
      planMode: planMode,
      restoreCount: 0,
      restoreBurstCount: 0,
      fullMediaHydrationCount: 0,
      metadataOnlyRestoreCount: 0,
      thumbnailDownloadCount: 0,
      fullImageDownloadCount: 0,
      pdfDownloadCount: 0,
      estimatedDownloadBytes: 0,
      estimatedUploadBytes: 0,
      repeatedSyncCount: 0,
      updatedAt: DateTime.now(),
    );
  }

  CloudObservationMetrics copyWith({
    String? scope,
    CloudEntitlementMode? planMode,
    int? restoreCount,
    int? restoreBurstCount,
    int? fullMediaHydrationCount,
    int? metadataOnlyRestoreCount,
    int? thumbnailDownloadCount,
    int? fullImageDownloadCount,
    int? pdfDownloadCount,
    int? estimatedDownloadBytes,
    int? estimatedUploadBytes,
    int? repeatedSyncCount,
    DateTime? lastRestoreAt,
    DateTime? lastHeavyDownloadAt,
    DateTime? lastSyncAt,
    DateTime? updatedAt,
    bool clearLastRestoreAt = false,
    bool clearLastHeavyDownloadAt = false,
    bool clearLastSyncAt = false,
  }) {
    return CloudObservationMetrics(
      scope: scope ?? this.scope,
      planMode: planMode ?? this.planMode,
      restoreCount: restoreCount ?? this.restoreCount,
      restoreBurstCount: restoreBurstCount ?? this.restoreBurstCount,
      fullMediaHydrationCount:
          fullMediaHydrationCount ?? this.fullMediaHydrationCount,
      metadataOnlyRestoreCount:
          metadataOnlyRestoreCount ?? this.metadataOnlyRestoreCount,
      thumbnailDownloadCount:
          thumbnailDownloadCount ?? this.thumbnailDownloadCount,
      fullImageDownloadCount:
          fullImageDownloadCount ?? this.fullImageDownloadCount,
      pdfDownloadCount: pdfDownloadCount ?? this.pdfDownloadCount,
      estimatedDownloadBytes:
          estimatedDownloadBytes ?? this.estimatedDownloadBytes,
      estimatedUploadBytes:
          estimatedUploadBytes ?? this.estimatedUploadBytes,
      repeatedSyncCount: repeatedSyncCount ?? this.repeatedSyncCount,
      lastRestoreAt:
          clearLastRestoreAt ? null : (lastRestoreAt ?? this.lastRestoreAt),
      lastHeavyDownloadAt: clearLastHeavyDownloadAt
          ? null
          : (lastHeavyDownloadAt ?? this.lastHeavyDownloadAt),
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      DbConstants.colCloudObservationScope: scope,
      DbConstants.colCloudObservationPlanMode: planMode.storageValue,
      DbConstants.colCloudObservationRestoreCount: restoreCount,
      DbConstants.colCloudObservationRestoreBurstCount: restoreBurstCount,
      DbConstants.colCloudObservationFullMediaHydrationCount:
          fullMediaHydrationCount,
      DbConstants.colCloudObservationMetadataOnlyRestoreCount:
          metadataOnlyRestoreCount,
      DbConstants.colCloudObservationThumbnailDownloadCount:
          thumbnailDownloadCount,
      DbConstants.colCloudObservationFullImageDownloadCount:
          fullImageDownloadCount,
      DbConstants.colCloudObservationPdfDownloadCount: pdfDownloadCount,
      DbConstants.colCloudObservationEstimatedDownloadBytes:
          estimatedDownloadBytes,
      DbConstants.colCloudObservationEstimatedUploadBytes:
          estimatedUploadBytes,
      DbConstants.colCloudObservationRepeatedSyncCount: repeatedSyncCount,
      DbConstants.colCloudObservationLastRestoreAt:
          lastRestoreAt?.millisecondsSinceEpoch,
      DbConstants.colCloudObservationLastHeavyDownloadAt:
          lastHeavyDownloadAt?.millisecondsSinceEpoch,
      DbConstants.colCloudObservationLastSyncAt:
          lastSyncAt?.millisecondsSinceEpoch,
      DbConstants.colCloudObservationUpdatedAt:
          updatedAt.millisecondsSinceEpoch,
    };
  }

  factory CloudObservationMetrics.fromMap(Map<String, Object?> map) {
    DateTime? parseDate(String key) {
      final rawValue = (map[key] as num?)?.toInt();
      if (rawValue == null) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(rawValue);
    }

    return CloudObservationMetrics(
      scope: map[DbConstants.colCloudObservationScope] as String? ?? '',
      planMode: CloudEntitlementMode.fromStorageValue(
        map[DbConstants.colCloudObservationPlanMode] as String?,
      ),
      restoreCount:
          (map[DbConstants.colCloudObservationRestoreCount] as num?)?.toInt() ??
              0,
      restoreBurstCount:
          (map[DbConstants.colCloudObservationRestoreBurstCount] as num?)
                  ?.toInt() ??
              0,
      fullMediaHydrationCount:
          (map[DbConstants.colCloudObservationFullMediaHydrationCount] as num?)
                  ?.toInt() ??
              0,
      metadataOnlyRestoreCount:
          (map[DbConstants.colCloudObservationMetadataOnlyRestoreCount]
                      as num?)
                  ?.toInt() ??
              0,
      thumbnailDownloadCount:
          (map[DbConstants.colCloudObservationThumbnailDownloadCount] as num?)
                  ?.toInt() ??
              0,
      fullImageDownloadCount:
          (map[DbConstants.colCloudObservationFullImageDownloadCount] as num?)
                  ?.toInt() ??
              0,
      pdfDownloadCount:
          (map[DbConstants.colCloudObservationPdfDownloadCount] as num?)
                  ?.toInt() ??
              0,
      estimatedDownloadBytes:
          (map[DbConstants.colCloudObservationEstimatedDownloadBytes] as num?)
                  ?.toInt() ??
              0,
      estimatedUploadBytes:
          (map[DbConstants.colCloudObservationEstimatedUploadBytes] as num?)
                  ?.toInt() ??
              0,
      repeatedSyncCount:
          (map[DbConstants.colCloudObservationRepeatedSyncCount] as num?)
                  ?.toInt() ??
              0,
      lastRestoreAt: parseDate(DbConstants.colCloudObservationLastRestoreAt),
      lastHeavyDownloadAt:
          parseDate(DbConstants.colCloudObservationLastHeavyDownloadAt),
      lastSyncAt: parseDate(DbConstants.colCloudObservationLastSyncAt),
      updatedAt:
          parseDate(DbConstants.colCloudObservationUpdatedAt) ?? DateTime.now(),
    );
  }
}
