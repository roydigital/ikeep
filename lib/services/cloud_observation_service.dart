import 'package:flutter/foundation.dart';

import '../core/constants/feature_limits.dart';
import '../data/database/cloud_observation_dao.dart';
import '../domain/models/cloud_entitlement.dart';
import '../domain/models/cloud_guardrail_observation.dart';
import '../domain/models/cloud_media_observation_activity.dart';
import '../domain/models/cloud_observation_metrics.dart';
import '../domain/models/media_cache_entry.dart';
import '../domain/models/sync_status.dart';

class CloudObservationService {
  CloudObservationService({
    required CloudObservationDao observationDao,
    this.planMode = CloudEntitlementMode.closedTestingFreeAccess,
  }) : _observationDao = observationDao;

  final CloudObservationDao _observationDao;
  final CloudEntitlementMode planMode;

  static const deviceScope = 'closed_testing_device';
  static const _restoreBurstWindow = Duration(hours: 12);
  static const _restoreWarnThreshold = 2;
  static const _restoreThrottleThreshold = 3;
  static const _restoreBlockThreshold = 5;
  static const _repeatMediaWarnThreshold = 3;
  static const _repeatMediaThrottleThreshold = 5;
  static const _repeatMediaBlockThreshold = 8;
  static const _heavyDownloadWarnBytes = 250 * 1024 * 1024;
  static const _heavyDownloadThrottleBytes = 500 * 1024 * 1024;
  static const _heavyDownloadBlockBytes = 1024 * 1024 * 1024;
  static const _noOpSyncWarnThreshold = 3;
  static const _noOpSyncThrottleThreshold = 5;
  static const _noOpSyncBlockThreshold = 8;

  Future<CloudObservationMetrics> getMetrics({
    String scope = deviceScope,
  }) async {
    return _loadMetrics(scope);
  }

  Future<List<CloudGuardrailObservation>> evaluateCurrentSignals() async {
    final metrics = await _loadMetrics(deviceScope);
    final activities = await _observationDao.getAllMediaActivities();
    final maxRepeatedFullMediaDownloads = activities
        .where(
          (activity) =>
              activity.mediaType == CachedMediaType.fullImage ||
              activity.mediaType == CachedMediaType.pdf,
        )
        .fold<int>(
          0,
          (maxCount, activity) => activity.downloadCount > maxCount
              ? activity.downloadCount
              : maxCount,
        );

    return [
      _evaluateObservation(
        scope: metrics.scope,
        reasonCode: CloudGuardrailReasonCode.repeatedRestoreBurst,
        currentObservedUsage: metrics.restoreBurstCount,
        warnThreshold: _restoreWarnThreshold,
        throttleThreshold: _restoreThrottleThreshold,
        blockThreshold: _restoreBlockThreshold,
        successMessage:
            'Restore activity is within expected Closed Testing usage.',
        warnMessage: 'Repeated restore activity would warn in production.',
        throttleMessage:
            'Repeated restore activity would throttle in production.',
        blockMessage: 'Repeated restore activity would block in production.',
      ),
      _evaluateObservation(
        scope: metrics.scope,
        reasonCode: CloudGuardrailReasonCode.repeatedUnchangedMediaDownload,
        currentObservedUsage: maxRepeatedFullMediaDownloads,
        warnThreshold: _repeatMediaWarnThreshold,
        throttleThreshold: _repeatMediaThrottleThreshold,
        blockThreshold: _repeatMediaBlockThreshold,
        successMessage:
            'Full-media download reuse is within expected Closed Testing usage.',
        warnMessage:
            'Repeated unchanged full-media downloads would warn in production.',
        throttleMessage:
            'Repeated unchanged full-media downloads would throttle in production.',
        blockMessage:
            'Repeated unchanged full-media downloads would block in production.',
      ),
      _evaluateObservation(
        scope: metrics.scope,
        reasonCode: CloudGuardrailReasonCode.heavyDownloadVolume,
        currentObservedUsage: metrics.estimatedDownloadBytes,
        warnThreshold: _heavyDownloadWarnBytes,
        throttleThreshold: _heavyDownloadThrottleBytes,
        blockThreshold: _heavyDownloadBlockBytes,
        successMessage:
            'Estimated download volume is within expected Closed Testing usage.',
        warnMessage: 'Estimated download volume would warn in production.',
        throttleMessage:
            'Estimated download volume would throttle in production.',
        blockMessage: 'Estimated download volume would block in production.',
      ),
      _evaluateObservation(
        scope: metrics.scope,
        reasonCode: CloudGuardrailReasonCode.repeatedNoOpSync,
        currentObservedUsage: metrics.repeatedSyncCount,
        warnThreshold: _noOpSyncWarnThreshold,
        throttleThreshold: _noOpSyncThrottleThreshold,
        blockThreshold: _noOpSyncBlockThreshold,
        successMessage: 'Sync cadence is within expected Closed Testing usage.',
        warnMessage: 'Repeated no-op sync runs would warn in production.',
        throttleMessage:
            'Repeated no-op sync runs would throttle in production.',
        blockMessage: 'Repeated no-op sync runs would block in production.',
      ),
    ];
  }

  Future<CloudGuardrailObservation> recordRestore({
    required String source,
    required bool metadataOnly,
  }) async {
    final now = DateTime.now();
    final existing = await _loadMetrics(deviceScope);
    final lastRestoreAt = existing.lastRestoreAt;
    final isBurst = lastRestoreAt != null &&
        now.difference(lastRestoreAt) <= _restoreBurstWindow;
    final restoreBurstCount = isBurst ? existing.restoreBurstCount + 1 : 1;
    final updated = existing.copyWith(
      planMode: planMode,
      restoreCount: existing.restoreCount + 1,
      restoreBurstCount: restoreBurstCount,
      metadataOnlyRestoreCount:
          existing.metadataOnlyRestoreCount + (metadataOnly ? 1 : 0),
      lastRestoreAt: now,
      updatedAt: now,
    );
    await _observationDao.upsertMetrics(updated);

    final observation = _evaluateObservation(
      scope: updated.scope,
      reasonCode: CloudGuardrailReasonCode.repeatedRestoreBurst,
      currentObservedUsage: restoreBurstCount,
      warnThreshold: _restoreWarnThreshold,
      throttleThreshold: _restoreThrottleThreshold,
      blockThreshold: _restoreBlockThreshold,
      successMessage: 'Restore activity is within expected Closed Testing usage.',
      warnMessage:
          'Repeated restore activity would warn in production.',
      throttleMessage:
          'Repeated restore activity would throttle in production.',
      blockMessage:
          'Repeated restore activity would block in production.',
    );
    _logObservation(
      'restore',
      observation,
      extra:
          'source=$source metadataOnly=$metadataOnly restoreCount=${updated.restoreCount}',
    );
    return observation;
  }

  Future<CloudGuardrailObservation> recordMediaDownload({
    required CachedMediaType mediaType,
    required String storagePath,
    int? version,
    String? contentHash,
    required int estimatedBytes,
    String source = 'media_cache_download',
  }) async {
    final now = DateTime.now();
    final normalizedStoragePath = storagePath.trim();
    final normalizedHash = _normalizedOrNull(contentHash);
    final bytes = estimatedBytes < 0 ? 0 : estimatedBytes;
    if (normalizedStoragePath.isEmpty) {
      return _withinExpectedUsage(deviceScope);
    }
    final metrics = await _loadMetrics(deviceScope);
    final activityKey = _activityKeyFor(
      mediaType: mediaType,
      storagePath: normalizedStoragePath,
      version: version,
      contentHash: normalizedHash,
    );
    final existingActivity =
        await _observationDao.getMediaActivity(activityKey) ??
            CloudMediaObservationActivity.initial(
              activityKey: activityKey,
              mediaType: mediaType,
              storagePath: normalizedStoragePath,
              version: version,
              contentHash: normalizedHash,
              now: now,
            );
    final nextActivity = existingActivity.copyWith(
      version: version,
      contentHash: normalizedHash,
      downloadCount: existingActivity.downloadCount + 1,
      totalDownloadedBytes: existingActivity.totalDownloadedBytes + bytes,
      lastDownloadedBytes: bytes,
      lastDownloadedAt: now,
      updatedAt: now,
    );
    await _observationDao.upsertMediaActivity(nextActivity);

    final isFullMedia = mediaType == CachedMediaType.fullImage ||
        mediaType == CachedMediaType.pdf;
    final nextMetrics = metrics.copyWith(
      planMode: planMode,
      fullMediaHydrationCount:
          metrics.fullMediaHydrationCount + (isFullMedia ? 1 : 0),
      thumbnailDownloadCount: metrics.thumbnailDownloadCount +
          (mediaType == CachedMediaType.thumbnail ? 1 : 0),
      fullImageDownloadCount: metrics.fullImageDownloadCount +
          (mediaType == CachedMediaType.fullImage ? 1 : 0),
      pdfDownloadCount:
          metrics.pdfDownloadCount + (mediaType == CachedMediaType.pdf ? 1 : 0),
      estimatedDownloadBytes: metrics.estimatedDownloadBytes + bytes,
      lastHeavyDownloadAt: isFullMedia || bytes >= targetFullImageBytes
          ? now
          : metrics.lastHeavyDownloadAt,
      updatedAt: now,
    );
    await _observationDao.upsertMetrics(nextMetrics);

    final repeatedDownloadObservation = isFullMedia
        ? _evaluateObservation(
            scope: nextMetrics.scope,
            reasonCode: CloudGuardrailReasonCode.repeatedUnchangedMediaDownload,
            currentObservedUsage: nextActivity.downloadCount,
            warnThreshold: _repeatMediaWarnThreshold,
            throttleThreshold: _repeatMediaThrottleThreshold,
            blockThreshold: _repeatMediaBlockThreshold,
            successMessage:
                'Full-media download reuse is within expected Closed Testing usage.',
            warnMessage:
                'Repeated unchanged full-media downloads would warn in production.',
            throttleMessage:
                'Repeated unchanged full-media downloads would throttle in production.',
            blockMessage:
                'Repeated unchanged full-media downloads would block in production.',
          )
        : _withinExpectedUsage(nextMetrics.scope);

    final heavyDownloadObservation = _evaluateObservation(
      scope: nextMetrics.scope,
      reasonCode: CloudGuardrailReasonCode.heavyDownloadVolume,
      currentObservedUsage: nextMetrics.estimatedDownloadBytes,
      warnThreshold: _heavyDownloadWarnBytes,
      throttleThreshold: _heavyDownloadThrottleBytes,
      blockThreshold: _heavyDownloadBlockBytes,
      successMessage:
          'Estimated download volume is within expected Closed Testing usage.',
      warnMessage: 'Estimated download volume would warn in production.',
      throttleMessage:
          'Estimated download volume would throttle in production.',
      blockMessage: 'Estimated download volume would block in production.',
    );

    final observation = _moreSevereObservation(
      repeatedDownloadObservation,
      heavyDownloadObservation,
    );
    _logObservation(
      'download',
      observation,
      extra:
          'source=$source type=${mediaType.dbValue} path=$normalizedStoragePath bytes=$bytes '
          'downloadCount=${nextActivity.downloadCount} totalBytes=${nextMetrics.estimatedDownloadBytes}',
    );
    return observation;
  }

  Future<void> recordUpload({
    required int estimatedBytes,
    required String source,
  }) async {
    final now = DateTime.now();
    final metrics = await _loadMetrics(deviceScope);
    final nextMetrics = metrics.copyWith(
      planMode: planMode,
      estimatedUploadBytes: metrics.estimatedUploadBytes +
          (estimatedBytes < 0 ? 0 : estimatedBytes),
      updatedAt: now,
    );
    await _observationDao.upsertMetrics(nextMetrics);
    debugPrint(
      '[IkeepObserve] upload tracked '
      'mode=${planMode.storageValue} source=$source bytes=$estimatedBytes '
      'totalUploadBytes=${nextMetrics.estimatedUploadBytes}',
    );
  }

  Future<CloudGuardrailObservation> recordSyncRun({
    required String source,
    required SyncResult result,
  }) async {
    final now = DateTime.now();
    final metrics = await _loadMetrics(deviceScope);
    final meaningfulChange = _hasMeaningfulSyncChange(result);
    final repeatedSyncCount =
        meaningfulChange || result.hasError || result.isTimedOut
            ? 0
            : metrics.repeatedSyncCount + 1;
    final nextMetrics = metrics.copyWith(
      planMode: planMode,
      repeatedSyncCount: repeatedSyncCount,
      lastSyncAt: now,
      updatedAt: now,
    );
    await _observationDao.upsertMetrics(nextMetrics);

    final observation = _evaluateObservation(
      scope: nextMetrics.scope,
      reasonCode: CloudGuardrailReasonCode.repeatedNoOpSync,
      currentObservedUsage: repeatedSyncCount,
      warnThreshold: _noOpSyncWarnThreshold,
      throttleThreshold: _noOpSyncThrottleThreshold,
      blockThreshold: _noOpSyncBlockThreshold,
      successMessage: 'Sync cadence is within expected Closed Testing usage.',
      warnMessage: 'Repeated no-op sync runs would warn in production.',
      throttleMessage:
          'Repeated no-op sync runs would throttle in production.',
      blockMessage: 'Repeated no-op sync runs would block in production.',
    );
    _logObservation(
      'sync',
      observation,
      extra:
          'source=$source meaningful=$meaningfulChange total=${result.totalItems} '
          'synced=${result.syncedItems} failed=${result.failedItems}',
    );
    return observation;
  }

  Future<CloudObservationMetrics> _loadMetrics(String scope) async {
    return await _observationDao.getMetrics(scope) ??
        CloudObservationMetrics.initial(
          scope: scope,
          planMode: planMode,
        );
  }

  CloudGuardrailObservation _withinExpectedUsage(String scope) {
    return CloudGuardrailObservation(
      scope: scope,
      planMode: planMode,
      allowedNow: true,
      reasonCode: CloudGuardrailReasonCode.withinExpectedUsage,
      productionAction: CloudGuardrailProductionAction.none,
      message: 'Usage is within expected Closed Testing bounds.',
      currentObservedUsage: 0,
      futureThreshold: 0,
    );
  }

  CloudGuardrailObservation _evaluateObservation({
    required String scope,
    required CloudGuardrailReasonCode reasonCode,
    required int currentObservedUsage,
    required int warnThreshold,
    required int throttleThreshold,
    required int blockThreshold,
    required String successMessage,
    required String warnMessage,
    required String throttleMessage,
    required String blockMessage,
  }) {
    if (currentObservedUsage >= blockThreshold) {
      return _buildObservation(
        scope: scope,
        reasonCode: reasonCode,
        action: CloudGuardrailProductionAction.block,
        currentObservedUsage: currentObservedUsage,
        futureThreshold: blockThreshold,
        message: blockMessage,
      );
    }
    if (currentObservedUsage >= throttleThreshold) {
      return _buildObservation(
        scope: scope,
        reasonCode: reasonCode,
        action: CloudGuardrailProductionAction.throttle,
        currentObservedUsage: currentObservedUsage,
        futureThreshold: throttleThreshold,
        message: throttleMessage,
      );
    }
    if (currentObservedUsage >= warnThreshold) {
      return _buildObservation(
        scope: scope,
        reasonCode: reasonCode,
        action: CloudGuardrailProductionAction.warn,
        currentObservedUsage: currentObservedUsage,
        futureThreshold: warnThreshold,
        message: warnMessage,
      );
    }
    return _buildObservation(
      scope: scope,
      reasonCode: CloudGuardrailReasonCode.withinExpectedUsage,
      action: CloudGuardrailProductionAction.none,
      currentObservedUsage: currentObservedUsage,
      futureThreshold: warnThreshold,
      message: successMessage,
    );
  }

  CloudGuardrailObservation _buildObservation({
    required String scope,
    required CloudGuardrailReasonCode reasonCode,
    required CloudGuardrailProductionAction action,
    required int currentObservedUsage,
    required int futureThreshold,
    required String message,
  }) {
    final allowedNow = !planMode.enforcesHardLimits ||
        action != CloudGuardrailProductionAction.block;
    final modeMessage = action == CloudGuardrailProductionAction.none
        ? message
        : '$message Allowed now because the app is in Closed Testing.';
    return CloudGuardrailObservation(
      scope: scope,
      planMode: planMode,
      allowedNow: allowedNow,
      reasonCode: reasonCode,
      productionAction: action,
      message: modeMessage,
      currentObservedUsage: currentObservedUsage,
      futureThreshold: futureThreshold,
    );
  }

  CloudGuardrailObservation _moreSevereObservation(
    CloudGuardrailObservation first,
    CloudGuardrailObservation second,
  ) {
    return first.productionAction.index >= second.productionAction.index
        ? first
        : second;
  }

  bool _hasMeaningfulSyncChange(SyncResult result) {
    return result.totalItems > 0 ||
        result.syncedItems > 0 ||
        result.failedItems > 0 ||
        result.itemOutcomes.isNotEmpty;
  }

  String _activityKeyFor({
    required CachedMediaType mediaType,
    required String storagePath,
    int? version,
    String? contentHash,
  }) {
    final versionPart = version?.toString() ?? 'noversion';
    final hashPart = _normalizedOrNull(contentHash) ?? 'nohash';
    return '${mediaType.dbValue}|$storagePath|$versionPart|$hashPart';
  }

  String? _normalizedOrNull(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void _logObservation(
    String event,
    CloudGuardrailObservation observation, {
    String? extra,
  }) {
    debugPrint(
      '[IkeepObserve] event=$event mode=${planMode.storageValue} '
      'action=${observation.productionAction.name} '
      'reason=${observation.reasonCode.name} '
      'usage=${observation.currentObservedUsage} '
      'threshold=${observation.futureThreshold}'
      '${extra == null || extra.isEmpty ? '' : ' $extra'}',
    );
  }
}
