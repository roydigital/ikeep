import '../../core/constants/db_constants.dart';

/// Persistent checkpoint for personal and household cloud delta sync.
///
/// One row is stored per sync scope so future phases can add independent
/// checkpoints without rewriting the current table shape.
class SyncCheckpointState {
  const SyncCheckpointState({
    required this.syncScope,
    this.householdId,
    this.lastSuccessfulPullAt,
    this.lastSuccessfulPushAt,
    this.lastFullSyncAt,
    this.lastKnownRemoteCheckpoint,
    required this.updatedAt,
  });

  final String syncScope;
  final String? householdId;
  final DateTime? lastSuccessfulPullAt;
  final DateTime? lastSuccessfulPushAt;
  final DateTime? lastFullSyncAt;
  final String? lastKnownRemoteCheckpoint;
  final DateTime updatedAt;

  DateTime? get latestSuccessfulSyncAt {
    final candidates = <DateTime>[
      if (lastSuccessfulPullAt != null) lastSuccessfulPullAt!,
      if (lastSuccessfulPushAt != null) lastSuccessfulPushAt!,
      if (lastFullSyncAt != null) lastFullSyncAt!,
    ];
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort();
    return candidates.last;
  }

  SyncCheckpointState copyWith({
    String? syncScope,
    String? householdId,
    DateTime? lastSuccessfulPullAt,
    DateTime? lastSuccessfulPushAt,
    DateTime? lastFullSyncAt,
    String? lastKnownRemoteCheckpoint,
    DateTime? updatedAt,
    bool clearHouseholdId = false,
    bool clearLastSuccessfulPullAt = false,
    bool clearLastSuccessfulPushAt = false,
    bool clearLastFullSyncAt = false,
    bool clearLastKnownRemoteCheckpoint = false,
  }) {
    return SyncCheckpointState(
      syncScope: syncScope ?? this.syncScope,
      householdId: clearHouseholdId ? null : (householdId ?? this.householdId),
      lastSuccessfulPullAt: clearLastSuccessfulPullAt
          ? null
          : (lastSuccessfulPullAt ?? this.lastSuccessfulPullAt),
      lastSuccessfulPushAt: clearLastSuccessfulPushAt
          ? null
          : (lastSuccessfulPushAt ?? this.lastSuccessfulPushAt),
      lastFullSyncAt:
          clearLastFullSyncAt ? null : (lastFullSyncAt ?? this.lastFullSyncAt),
      lastKnownRemoteCheckpoint: clearLastKnownRemoteCheckpoint
          ? null
          : (lastKnownRemoteCheckpoint ?? this.lastKnownRemoteCheckpoint),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      DbConstants.colSyncCheckpointScope: syncScope,
      DbConstants.colSyncCheckpointHouseholdId: householdId,
      DbConstants.colSyncCheckpointLastPullAt:
          lastSuccessfulPullAt?.millisecondsSinceEpoch,
      DbConstants.colSyncCheckpointLastPushAt:
          lastSuccessfulPushAt?.millisecondsSinceEpoch,
      DbConstants.colSyncCheckpointLastFullSyncAt:
          lastFullSyncAt?.millisecondsSinceEpoch,
      DbConstants.colSyncCheckpointRemoteCursor: lastKnownRemoteCheckpoint,
      DbConstants.colSyncCheckpointUpdatedAt: updatedAt.millisecondsSinceEpoch,
    };
  }

  factory SyncCheckpointState.fromMap(Map<String, Object?> map) {
    return SyncCheckpointState(
      syncScope: map[DbConstants.colSyncCheckpointScope] as String? ?? '',
      householdId: map[DbConstants.colSyncCheckpointHouseholdId] as String?,
      lastSuccessfulPullAt: _dateTimeFromValue(
        map[DbConstants.colSyncCheckpointLastPullAt],
      ),
      lastSuccessfulPushAt: _dateTimeFromValue(
        map[DbConstants.colSyncCheckpointLastPushAt],
      ),
      lastFullSyncAt: _dateTimeFromValue(
        map[DbConstants.colSyncCheckpointLastFullSyncAt],
      ),
      lastKnownRemoteCheckpoint:
          map[DbConstants.colSyncCheckpointRemoteCursor] as String?,
      updatedAt: _dateTimeFromValue(
            map[DbConstants.colSyncCheckpointUpdatedAt],
          ) ??
          DateTime.now(),
    );
  }

  static DateTime? _dateTimeFromValue(Object? value) {
    final millis = (value as num?)?.toInt();
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
