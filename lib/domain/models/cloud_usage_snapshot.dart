import '../../core/constants/db_constants.dart';
import 'cloud_entitlement.dart';

class CloudUsageSnapshot {
  const CloudUsageSnapshot({
    required this.scope,
    this.householdId,
    required this.planMode,
    required this.backedUpItemCount,
    required this.totalImageCount,
    required this.totalPdfCount,
    required this.totalStoredBytes,
    required this.householdMemberCount,
    required this.updatedAt,
  });

  final String scope;
  final String? householdId;
  final CloudEntitlementMode planMode;
  final int backedUpItemCount;
  final int totalImageCount;
  final int totalPdfCount;
  final int totalStoredBytes;
  final int householdMemberCount;
  final DateTime updatedAt;

  CloudUsageSnapshot copyWith({
    String? scope,
    String? householdId,
    CloudEntitlementMode? planMode,
    int? backedUpItemCount,
    int? totalImageCount,
    int? totalPdfCount,
    int? totalStoredBytes,
    int? householdMemberCount,
    DateTime? updatedAt,
    bool clearHouseholdId = false,
  }) {
    return CloudUsageSnapshot(
      scope: scope ?? this.scope,
      householdId: clearHouseholdId ? null : (householdId ?? this.householdId),
      planMode: planMode ?? this.planMode,
      backedUpItemCount: backedUpItemCount ?? this.backedUpItemCount,
      totalImageCount: totalImageCount ?? this.totalImageCount,
      totalPdfCount: totalPdfCount ?? this.totalPdfCount,
      totalStoredBytes: totalStoredBytes ?? this.totalStoredBytes,
      householdMemberCount: householdMemberCount ?? this.householdMemberCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      DbConstants.colCloudUsageScope: scope,
      DbConstants.colCloudUsageHouseholdId: householdId,
      DbConstants.colCloudUsagePlanMode: planMode.storageValue,
      DbConstants.colCloudUsageBackedUpItemCount: backedUpItemCount,
      DbConstants.colCloudUsageTotalImageCount: totalImageCount,
      DbConstants.colCloudUsageTotalPdfCount: totalPdfCount,
      DbConstants.colCloudUsageTotalStoredBytes: totalStoredBytes,
      DbConstants.colCloudUsageHouseholdMemberCount: householdMemberCount,
      DbConstants.colCloudUsageUpdatedAt: updatedAt.millisecondsSinceEpoch,
    };
  }

  factory CloudUsageSnapshot.fromMap(Map<String, Object?> map) {
    return CloudUsageSnapshot(
      scope: map[DbConstants.colCloudUsageScope] as String? ?? '',
      householdId: map[DbConstants.colCloudUsageHouseholdId] as String?,
      planMode: CloudEntitlementMode.fromStorageValue(
        map[DbConstants.colCloudUsagePlanMode] as String?,
      ),
      backedUpItemCount:
          (map[DbConstants.colCloudUsageBackedUpItemCount] as num?)?.toInt() ??
              0,
      totalImageCount:
          (map[DbConstants.colCloudUsageTotalImageCount] as num?)?.toInt() ?? 0,
      totalPdfCount:
          (map[DbConstants.colCloudUsageTotalPdfCount] as num?)?.toInt() ?? 0,
      totalStoredBytes:
          (map[DbConstants.colCloudUsageTotalStoredBytes] as num?)?.toInt() ??
              0,
      householdMemberCount:
          (map[DbConstants.colCloudUsageHouseholdMemberCount] as num?)
              ?.toInt() ??
              0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map[DbConstants.colCloudUsageUpdatedAt] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
