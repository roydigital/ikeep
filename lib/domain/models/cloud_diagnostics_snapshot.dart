import 'cloud_entitlement.dart';
import 'cloud_observation_metrics.dart';
import 'cloud_usage_snapshot.dart';
import 'sync_checkpoint_state.dart';

class CloudDiagnosticsGuardrailSummary {
  const CloudDiagnosticsGuardrailSummary({
    required this.title,
    required this.source,
    required this.wouldWarnInProduction,
    required this.wouldThrottleInProduction,
    required this.wouldBlockInProduction,
    required this.reasonCode,
    required this.currentObservedUsage,
    required this.futureThreshold,
    required this.message,
  });

  final String title;
  final String source;
  final bool wouldWarnInProduction;
  final bool wouldThrottleInProduction;
  final bool wouldBlockInProduction;
  final String reasonCode;
  final int currentObservedUsage;
  final int futureThreshold;
  final String message;

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'source': source,
      'wouldWarnInProduction': wouldWarnInProduction,
      'wouldThrottleInProduction': wouldThrottleInProduction,
      'wouldBlockInProduction': wouldBlockInProduction,
      'reasonCode': reasonCode,
      'currentObservedUsage': currentObservedUsage,
      'futureThreshold': futureThreshold,
      'message': message,
    };
  }
}

class MediaCacheDiagnosticsSummary {
  const MediaCacheDiagnosticsSummary({
    required this.thumbnailCount,
    required this.fullImageCount,
    required this.pdfCount,
    required this.invalidEntryCount,
    required this.orphanFileCount,
    required this.estimatedCacheBytes,
  });

  final int thumbnailCount;
  final int fullImageCount;
  final int pdfCount;
  final int invalidEntryCount;
  final int orphanFileCount;
  final int estimatedCacheBytes;

  int get totalCachedEntryCount => thumbnailCount + fullImageCount + pdfCount;

  Map<String, Object?> toJson() {
    return {
      'thumbnailCount': thumbnailCount,
      'fullImageCount': fullImageCount,
      'pdfCount': pdfCount,
      'invalidEntryCount': invalidEntryCount,
      'orphanFileCount': orphanFileCount,
      'estimatedCacheBytes': estimatedCacheBytes,
    };
  }
}

class CloudDiagnosticsSnapshot {
  const CloudDiagnosticsSnapshot({
    required this.buildLabel,
    required this.planMode,
    required this.paywallActive,
    required this.quotaTrackingActive,
    required this.usageSnapshots,
    required this.observationMetrics,
    required this.guardrails,
    required this.syncCheckpoints,
    required this.pendingSyncCounts,
    required this.cacheSummary,
    required this.fallbackSummary,
    required this.generatedAt,
  });

  final String buildLabel;
  final CloudEntitlementMode planMode;
  final bool paywallActive;
  final bool quotaTrackingActive;
  final List<CloudUsageSnapshot> usageSnapshots;
  final CloudObservationMetrics observationMetrics;
  final List<CloudDiagnosticsGuardrailSummary> guardrails;
  final List<SyncCheckpointState> syncCheckpoints;
  final Map<String, int> pendingSyncCounts;
  final MediaCacheDiagnosticsSummary cacheSummary;
  final String fallbackSummary;
  final DateTime generatedAt;

  bool get hardEnforcementActive => planMode.enforcesHardLimits;
  int get pendingSyncTotal => pendingSyncCounts.values.fold(0, (a, b) => a + b);

  SyncCheckpointState? get personalCheckpoint {
    for (final checkpoint in syncCheckpoints) {
      if ((checkpoint.householdId?.trim().isEmpty ?? true)) {
        return checkpoint;
      }
    }
    return null;
  }

  List<SyncCheckpointState> get householdCheckpoints {
    return syncCheckpoints
        .where((checkpoint) => (checkpoint.householdId?.trim().isNotEmpty ?? false))
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return {
      'buildLabel': buildLabel,
      'planMode': planMode.storageValue,
      'hardEnforcementActive': hardEnforcementActive,
      'paywallActive': paywallActive,
      'quotaTrackingActive': quotaTrackingActive,
      'usageSnapshots': usageSnapshots.map((snapshot) => snapshot.toMap()).toList(),
      'observationMetrics': observationMetrics.toMap(),
      'guardrails': guardrails.map((guardrail) => guardrail.toJson()).toList(),
      'syncCheckpoints':
          syncCheckpoints.map((checkpoint) => checkpoint.toMap()).toList(),
      'pendingSyncCounts': pendingSyncCounts,
      'cacheSummary': cacheSummary.toJson(),
      'fallbackSummary': fallbackSummary,
      'generatedAt': generatedAt.toIso8601String(),
    };
  }
}
