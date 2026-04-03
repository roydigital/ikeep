import 'package:flutter/foundation.dart';

import '../core/constants/feature_limits.dart';
import '../data/database/cloud_usage_snapshot_dao.dart';
import '../data/database/household_member_dao.dart';
import '../data/database/item_dao.dart';
import '../data/database/pending_sync_dao.dart';
import '../data/database/sync_checkpoint_dao.dart';
import '../domain/models/cloud_diagnostics_snapshot.dart';
import '../domain/models/cloud_entitlement.dart';
import '../domain/models/cloud_guardrail_observation.dart';
import '../domain/models/cloud_usage_snapshot.dart';
import '../domain/models/item.dart';
import '../domain/models/sync_checkpoint_state.dart';
import '../services/app_info_service.dart';
import '../services/cloud_observation_service.dart';
import '../services/cloud_quota_service.dart';
import '../services/media_cache_service.dart';

class CloudDiagnosticsService {
  CloudDiagnosticsService({
    required AppInfoService appInfoService,
    required CloudEntitlementMode planMode,
    required CloudQuotaService cloudQuotaService,
    required CloudObservationService cloudObservationService,
    required CloudUsageSnapshotDao usageSnapshotDao,
    required SyncCheckpointDao syncCheckpointDao,
    required PendingSyncDao pendingSyncDao,
    required MediaCacheService mediaCacheService,
    required ItemDao itemDao,
    required HouseholdMemberDao householdMemberDao,
  })  : _appInfoService = appInfoService,
        _planMode = planMode,
        _cloudQuotaService = cloudQuotaService,
        _cloudObservationService = cloudObservationService,
        _usageSnapshotDao = usageSnapshotDao,
        _syncCheckpointDao = syncCheckpointDao,
        _pendingSyncDao = pendingSyncDao,
        _mediaCacheService = mediaCacheService,
        _itemDao = itemDao,
        _householdMemberDao = householdMemberDao;

  final AppInfoService _appInfoService;
  final CloudEntitlementMode _planMode;
  final CloudQuotaService _cloudQuotaService;
  final CloudObservationService _cloudObservationService;
  final CloudUsageSnapshotDao _usageSnapshotDao;
  final SyncCheckpointDao _syncCheckpointDao;
  final PendingSyncDao _pendingSyncDao;
  final MediaCacheService _mediaCacheService;
  final ItemDao _itemDao;
  final HouseholdMemberDao _householdMemberDao;

  Future<CloudDiagnosticsSnapshot> loadSnapshot() async {
    await _refreshUsageSnapshots();
    final buildLabel = await _appInfoService.getBuildLabel();

    final usageSnapshots = await _usageSnapshotDao.getAll();
    final observationMetrics = await _cloudObservationService.getMetrics();
    final observationSignals =
        await _cloudObservationService.evaluateCurrentSignals();
    final syncCheckpoints = await _syncCheckpointDao.getAll();
    final pendingOperations = await _pendingSyncDao.getAll();
    final cacheSummary = await _mediaCacheService.inspectCacheSummary();
    final items = await _itemDao.getAllItems(includeArchived: true);

    final guardrails = <CloudDiagnosticsGuardrailSummary>[
      ...observationSignals.map(_guardrailFromObservation),
      ..._buildQuotaGuardrails(
        usageSnapshots: usageSnapshots,
        items: items,
      ),
    ]..sort(_compareGuardrailSeverity);

    final pendingSyncCounts = <String, int>{};
    for (final operation in pendingOperations) {
      pendingSyncCounts.update(
        operation.entityType,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    return CloudDiagnosticsSnapshot(
      buildLabel: buildLabel,
      planMode: _planMode,
      paywallActive: false,
      quotaTrackingActive: true,
      usageSnapshots: _sortedUsageSnapshots(usageSnapshots),
      observationMetrics: observationMetrics,
      guardrails: guardrails,
      syncCheckpoints: _sortedCheckpoints(syncCheckpoints),
      pendingSyncCounts: pendingSyncCounts,
      cacheSummary: cacheSummary,
      fallbackSummary: 'Full-sync fallback reasons are not persisted yet.',
      generatedAt: DateTime.now(),
    );
  }

  Future<void> _refreshUsageSnapshots() async {
    try {
      await _cloudQuotaService.refreshPersonalUsage();
    } catch (error) {
      debugPrint(
        '[IkeepDiagnostics] personal usage refresh failed error=$error',
      );
    }
    final householdIds = await _discoverKnownHouseholdIds();
    for (final householdId in householdIds) {
      try {
        await _cloudQuotaService.refreshHouseholdUsage(householdId);
      } catch (error) {
        debugPrint(
          '[IkeepDiagnostics] household usage refresh failed '
          'household=$householdId error=$error',
        );
      }
    }
  }

  Future<List<String>> _discoverKnownHouseholdIds() async {
    final ids = <String>{};
    final usageSnapshots = await _usageSnapshotDao.getAll();
    for (final snapshot in usageSnapshots) {
      final householdId = snapshot.householdId?.trim();
      if (householdId != null && householdId.isNotEmpty) {
        ids.add(householdId);
      }
    }

    final items = await _itemDao.getAllItems(includeArchived: true);
    for (final item in items) {
      final householdId = item.householdId?.trim();
      if (householdId != null && householdId.isNotEmpty) {
        ids.add(householdId);
      }
    }

    final members = await _householdMemberDao.getAllMembers();
    for (final member in members) {
      final householdId = member.householdId?.trim();
      if (householdId != null && householdId.isNotEmpty) {
        ids.add(householdId);
      }
    }

    final sortedIds = ids.toList()..sort();
    return sortedIds;
  }

  List<CloudUsageSnapshot> _sortedUsageSnapshots(
    List<CloudUsageSnapshot> snapshots,
  ) {
    final sorted = List<CloudUsageSnapshot>.from(snapshots);
    sorted.sort((a, b) {
      final aIsPersonal = a.scope == CloudQuotaService.personalScope;
      final bIsPersonal = b.scope == CloudQuotaService.personalScope;
      if (aIsPersonal != bIsPersonal) {
        return aIsPersonal ? -1 : 1;
      }
      final householdCompare =
          (a.householdId ?? '').compareTo(b.householdId ?? '');
      if (householdCompare != 0) {
        return householdCompare;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return sorted;
  }

  List<CloudDiagnosticsGuardrailSummary> _buildQuotaGuardrails({
    required List<CloudUsageSnapshot> usageSnapshots,
    required List<Item> items,
  }) {
    final summaries = <CloudDiagnosticsGuardrailSummary>[];
    CloudUsageSnapshot? personalSnapshot;
    for (final snapshot in usageSnapshots) {
      if (snapshot.scope == CloudQuotaService.personalScope) {
        personalSnapshot = snapshot;
        break;
      }
    }

    if (personalSnapshot != null) {
      final backedUpCount = personalSnapshot.backedUpItemCount;
      if (backedUpCount > cloudBackupLimit) {
        summaries.add(
          _quotaGuardrail(
            title: 'Personal cloud item cap exceeded',
            source: 'quota:personal_items',
            reasonCode: CloudQuotaReasonCode.backedUpItemLimit.name,
            currentObservedUsage: backedUpCount,
            futureThreshold: cloudBackupLimit,
            wouldWarn: true,
            wouldThrottle: false,
            wouldBlock: true,
            message:
                'Cloud-backed item count is above the future paid-plan limit.',
          ),
        );
      } else if (backedUpCount >= cloudBackupWarningThreshold) {
        summaries.add(
          _quotaGuardrail(
            title: 'Personal cloud item cap nearing limit',
            source: 'quota:personal_items',
            reasonCode: CloudQuotaReasonCode.backedUpItemLimit.name,
            currentObservedUsage: backedUpCount,
            futureThreshold: cloudBackupLimit,
            wouldWarn: true,
            wouldThrottle: false,
            wouldBlock: false,
            message:
                'Cloud-backed item count is near the future paid-plan limit.',
          ),
        );
      }
    }

    for (final snapshot in usageSnapshots) {
      final householdId = snapshot.householdId?.trim();
      if (householdId == null || householdId.isEmpty) {
        continue;
      }
      final memberCount = snapshot.householdMemberCount;
      if (memberCount > householdMemberLimit) {
        summaries.add(
          _quotaGuardrail(
            title: 'Household member cap exceeded',
            source: 'quota:household_members:$householdId',
            reasonCode: CloudQuotaReasonCode.householdMemberLimit.name,
            currentObservedUsage: memberCount,
            futureThreshold: householdMemberLimit,
            wouldWarn: true,
            wouldThrottle: false,
            wouldBlock: true,
            message: 'Household membership is above the future paid-plan cap.',
          ),
        );
      } else if (memberCount >= householdMemberLimit - 1) {
        summaries.add(
          _quotaGuardrail(
            title: 'Household member cap nearing limit',
            source: 'quota:household_members:$householdId',
            reasonCode: CloudQuotaReasonCode.householdMemberLimit.name,
            currentObservedUsage: memberCount,
            futureThreshold: householdMemberLimit,
            wouldWarn: true,
            wouldThrottle: false,
            wouldBlock: false,
            message: 'Household membership is near the future paid-plan cap.',
          ),
        );
      }
    }

    var maxImageCount = 0;
    var maxPdfCount = 0;
    for (final item in items) {
      final imageCount =
          item.imagePaths.where((path) => path.trim().isNotEmpty).length;
      if (imageCount > maxImageCount) {
        maxImageCount = imageCount;
      }
      final pdfCount = (item.invoicePath?.trim().isNotEmpty ?? false) ? 1 : 0;
      if (pdfCount > maxPdfCount) {
        maxPdfCount = pdfCount;
      }
    }

    if (maxImageCount > itemPhotoLimit) {
      summaries.add(
        _quotaGuardrail(
          title: 'Item image cap exceeded',
          source: 'quota:item_images',
          reasonCode: CloudQuotaReasonCode.imagesPerItemLimit.name,
          currentObservedUsage: maxImageCount,
          futureThreshold: itemPhotoLimit,
          wouldWarn: true,
          wouldThrottle: false,
          wouldBlock: true,
          message: 'At least one item exceeds the future image-per-item limit.',
        ),
      );
    }

    if (maxPdfCount > itemPdfLimit) {
      summaries.add(
        _quotaGuardrail(
          title: 'Item PDF cap exceeded',
          source: 'quota:item_pdfs',
          reasonCode: CloudQuotaReasonCode.pdfPerItemLimit.name,
          currentObservedUsage: maxPdfCount,
          futureThreshold: itemPdfLimit,
          wouldWarn: true,
          wouldThrottle: false,
          wouldBlock: true,
          message: 'At least one item exceeds the future PDF-per-item limit.',
        ),
      );
    }

    return summaries;
  }

  CloudDiagnosticsGuardrailSummary _quotaGuardrail({
    required String title,
    required String source,
    required String reasonCode,
    required int currentObservedUsage,
    required int futureThreshold,
    required bool wouldWarn,
    required bool wouldThrottle,
    required bool wouldBlock,
    required String message,
  }) {
    return CloudDiagnosticsGuardrailSummary(
      title: title,
      source: source,
      wouldWarnInProduction: wouldWarn,
      wouldThrottleInProduction: wouldThrottle,
      wouldBlockInProduction: wouldBlock,
      reasonCode: reasonCode,
      currentObservedUsage: currentObservedUsage,
      futureThreshold: futureThreshold,
      message: message,
    );
  }

  CloudDiagnosticsGuardrailSummary _guardrailFromObservation(
    CloudGuardrailObservation observation,
  ) {
    return CloudDiagnosticsGuardrailSummary(
      title: _guardrailTitle(observation.reasonCode),
      source: 'observation:${observation.reasonCode.name}',
      wouldWarnInProduction: observation.wouldWarnInProduction,
      wouldThrottleInProduction: observation.wouldThrottleInProduction,
      wouldBlockInProduction: observation.wouldBlockInProduction,
      reasonCode: observation.reasonCode.name,
      currentObservedUsage: observation.currentObservedUsage,
      futureThreshold: observation.futureThreshold,
      message: observation.message,
    );
  }

  String _guardrailTitle(CloudGuardrailReasonCode reasonCode) {
    return switch (reasonCode) {
      CloudGuardrailReasonCode.withinExpectedUsage =>
        'Usage within expected range',
      CloudGuardrailReasonCode.repeatedRestoreBurst =>
        'Repeated restore activity',
      CloudGuardrailReasonCode.repeatedUnchangedMediaDownload =>
        'Repeated unchanged full-media downloads',
      CloudGuardrailReasonCode.heavyDownloadVolume =>
        'Heavy cumulative download volume',
      CloudGuardrailReasonCode.repeatedNoOpSync => 'Repeated no-op sync runs',
    };
  }

  int _compareGuardrailSeverity(
    CloudDiagnosticsGuardrailSummary a,
    CloudDiagnosticsGuardrailSummary b,
  ) {
    int score(CloudDiagnosticsGuardrailSummary summary) {
      if (summary.wouldBlockInProduction) return 3;
      if (summary.wouldThrottleInProduction) return 2;
      if (summary.wouldWarnInProduction) return 1;
      return 0;
    }

    return score(b).compareTo(score(a));
  }

  List<SyncCheckpointState> _sortedCheckpoints(
    List<SyncCheckpointState> checkpoints,
  ) {
    final sorted = List<SyncCheckpointState>.from(checkpoints);
    sorted.sort((a, b) {
      final aIsPersonal = (a.householdId?.trim().isEmpty ?? true);
      final bIsPersonal = (b.householdId?.trim().isEmpty ?? true);
      if (aIsPersonal != bIsPersonal) {
        return aIsPersonal ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return sorted;
  }
}
