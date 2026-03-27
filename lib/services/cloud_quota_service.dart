import 'package:flutter/foundation.dart';

import '../core/constants/feature_limits.dart';
import '../data/database/cloud_usage_snapshot_dao.dart';
import '../data/database/household_member_dao.dart';
import '../data/database/item_cloud_media_dao.dart';
import '../data/database/item_dao.dart';
import '../domain/models/cloud_entitlement.dart';
import '../domain/models/cloud_usage_snapshot.dart';
import '../domain/models/item.dart';
import '../domain/models/item_cloud_media_reference.dart';
import '../domain/models/item_visibility.dart';

class CloudQuotaService {
  CloudQuotaService({
    required ItemDao itemDao,
    required ItemCloudMediaDao itemCloudMediaDao,
    required HouseholdMemberDao householdMemberDao,
    required CloudUsageSnapshotDao snapshotDao,
    this.planMode = CloudEntitlementMode.closedTestingFreeAccess,
  })  : _itemDao = itemDao,
        _itemCloudMediaDao = itemCloudMediaDao,
        _householdMemberDao = householdMemberDao,
        _snapshotDao = snapshotDao;

  final ItemDao _itemDao;
  final ItemCloudMediaDao _itemCloudMediaDao;
  final HouseholdMemberDao _householdMemberDao;
  final CloudUsageSnapshotDao _snapshotDao;
  final CloudEntitlementMode planMode;

  static const personalScope = 'personal_cloud_plan';
  static const householdScopePrefix = 'household_cloud_plan';

  String householdScope(String householdId) =>
      '$householdScopePrefix:$householdId';

  Future<CloudUsageSnapshot?> getSnapshot(String scope) {
    return _snapshotDao.getByScope(scope);
  }

  Future<CloudUsageSnapshot> refreshPersonalUsage() async {
    final items = await _itemDao.getAllItems(includeArchived: true);
    final cloudItems = items.where(_isCloudTrackedItem).toList(growable: false);
    final snapshot = await _buildSnapshot(
      scope: personalScope,
      householdId: null,
      items: cloudItems,
      householdMemberCount: 0,
    );
    await _snapshotDao.upsert(snapshot);
    _logUsageSnapshot('personal_recalc', snapshot);
    return snapshot;
  }

  Future<CloudUsageSnapshot> refreshHouseholdUsage(String householdId) async {
    final items = await _itemDao.getAllItems(includeArchived: true);
    final householdItems = items
        .where(
          (item) =>
              _isCloudTrackedItem(item) &&
              item.visibility == ItemVisibility.household &&
              (item.householdId?.trim() ?? '') == householdId.trim(),
        )
        .toList(growable: false);
    final memberCount =
        await _householdMemberDao.countMembersForHousehold(householdId);
    final snapshot = await _buildSnapshot(
      scope: householdScope(householdId),
      householdId: householdId,
      items: householdItems,
      householdMemberCount: memberCount,
    );
    await _snapshotDao.upsert(snapshot);
    _logUsageSnapshot('household_recalc', snapshot);
    return snapshot;
  }

  Future<CloudQuotaEvaluation> evaluatePersonalItemWrite(Item item) async {
    final snapshot = await refreshPersonalUsage();
    return _evaluateItemWrite(
      scope: personalScope,
      snapshot: snapshot,
      item: item,
      treatAsCloudTrackedWrite: true,
    );
  }

  Future<CloudQuotaEvaluation> evaluateSharedItemWrite({
    required String householdId,
    required Item item,
  }) async {
    await refreshHouseholdUsage(householdId);
    final snapshot = await refreshPersonalUsage();
    return _evaluateItemWrite(
      scope: householdScope(householdId),
      snapshot: snapshot,
      item: item,
      treatAsCloudTrackedWrite: true,
    );
  }

  Future<CloudQuotaEvaluation> evaluateHouseholdMemberAddition({
    required String householdId,
    int additionalMembers = 1,
  }) async {
    final snapshot = await refreshHouseholdUsage(householdId);
    final currentUsage = snapshot.householdMemberCount + additionalMembers;
    final wouldBlock = currentUsage > householdMemberLimit;
    final evaluation = _buildEvaluation(
      scope: householdScope(householdId),
      wouldBlockInPaidMode: wouldBlock,
      reasonCode: CloudQuotaReasonCode.householdMemberLimit,
      currentUsage: currentUsage,
      futureLimit: householdMemberLimit,
      successMessage: 'Household member count is within the future paid-plan cap.',
      blockedMessage:
          'Adding this member would exceed the future paid-plan household cap.',
    );
    _logEvaluation('member_addition', evaluation);
    return evaluation;
  }

  Future<CloudQuotaEvaluation> _evaluateItemWrite({
    required String scope,
    required CloudUsageSnapshot snapshot,
    required Item item,
    required bool treatAsCloudTrackedWrite,
  }) async {
    final imageCount =
        item.imagePaths.where((path) => path.trim().isNotEmpty).length;
    if (imageCount > itemPhotoLimit) {
      final evaluation = _buildEvaluation(
        scope: scope,
        wouldBlockInPaidMode: true,
        reasonCode: CloudQuotaReasonCode.imagesPerItemLimit,
        currentUsage: imageCount,
        futureLimit: itemPhotoLimit,
        successMessage: 'Item image count is within the future paid-plan limit.',
        blockedMessage:
            'This item exceeds the future paid-plan image-per-item limit.',
      );
      _logEvaluation('item_write', evaluation);
      return evaluation;
    }

    final pdfCount = (item.invoicePath?.trim().isNotEmpty ?? false) ? 1 : 0;
    if (pdfCount > itemPdfLimit) {
      final evaluation = _buildEvaluation(
        scope: scope,
        wouldBlockInPaidMode: true,
        reasonCode: CloudQuotaReasonCode.pdfPerItemLimit,
        currentUsage: pdfCount,
        futureLimit: itemPdfLimit,
        successMessage: 'Item PDF count is within the future paid-plan limit.',
        blockedMessage:
            'This item exceeds the future paid-plan PDF-per-item limit.',
      );
      _logEvaluation('item_write', evaluation);
      return evaluation;
    }

    final existingContribution = await _existingContributionForItem(item);
    var predictedBackedUpItemCount = snapshot.backedUpItemCount -
        (existingContribution.isTrackedItem ? 1 : 0) +
        (treatAsCloudTrackedWrite ? 1 : 0);
    if (predictedBackedUpItemCount < 0) {
      predictedBackedUpItemCount = 0;
    }
    final wouldBlock = predictedBackedUpItemCount > cloudBackupLimit;
    final evaluation = _buildEvaluation(
      scope: scope,
      wouldBlockInPaidMode: wouldBlock,
      reasonCode: CloudQuotaReasonCode.backedUpItemLimit,
      currentUsage: predictedBackedUpItemCount,
      futureLimit: cloudBackupLimit,
      successMessage:
          'Cloud-backed item count is within the future paid-plan limit.',
      blockedMessage:
          'Syncing this item would exceed the future paid-plan item limit.',
    );
    _logEvaluation('item_write', evaluation);
    return evaluation;
  }

  CloudQuotaEvaluation _buildEvaluation({
    required String scope,
    required bool wouldBlockInPaidMode,
    required CloudQuotaReasonCode reasonCode,
    required int currentUsage,
    required int futureLimit,
    required String successMessage,
    required String blockedMessage,
  }) {
    final allowedNow = !planMode.enforcesHardLimits || !wouldBlockInPaidMode;
    final message = wouldBlockInPaidMode
        ? planMode == CloudEntitlementMode.closedTestingFreeAccess
            ? '$blockedMessage Allowed now because the app is in Closed Testing.'
            : blockedMessage
        : successMessage;
    return CloudQuotaEvaluation(
      scope: scope,
      planMode: planMode,
      allowedNow: allowedNow,
      wouldBlockInPaidMode: wouldBlockInPaidMode,
      reasonCode: wouldBlockInPaidMode
          ? reasonCode
          : CloudQuotaReasonCode.withinLimits,
      message: message,
      currentUsage: currentUsage,
      futureLimit: futureLimit,
    );
  }

  Future<CloudUsageSnapshot> _buildSnapshot({
    required String scope,
    required String? householdId,
    required List<Item> items,
    required int householdMemberCount,
  }) async {
    final references = await _itemCloudMediaDao.getAllReferences();
    final refsByItem = <String, List<ItemCloudMediaReference>>{};
    for (final reference in references) {
      refsByItem.putIfAbsent(reference.itemUuid, () => <ItemCloudMediaReference>[])
          .add(reference);
    }

    final fullImagePaths = <String>{};
    final pdfPaths = <String>{};
    final storedPaths = <String>{};
    var totalStoredBytes = 0;
    var totalImageCount = 0;
    var totalPdfCount = 0;

    for (final item in items) {
      final itemReferences =
          refsByItem[item.uuid] ?? const <ItemCloudMediaReference>[];
      final imageRefs = itemReferences
          .where((reference) => reference.mediaRole == ItemCloudMediaRole.image)
          .toList(growable: false);
      ItemCloudMediaReference? invoiceRef;
      for (final reference in itemReferences) {
        if (reference.mediaRole == ItemCloudMediaRole.invoice) {
          invoiceRef = reference;
          break;
        }
      }

      if (imageRefs.isNotEmpty) {
        for (final reference in imageRefs) {
          if (fullImagePaths.add(reference.storagePath)) {
            totalImageCount++;
          }
          totalStoredBytes += _storedBytesForImage(reference);
          storedPaths.add(reference.storagePath);
          final thumbnailPath = reference.thumbnailPath?.trim();
          if (thumbnailPath != null &&
              thumbnailPath.isNotEmpty &&
              storedPaths.add(thumbnailPath)) {
            totalStoredBytes += _estimatedThumbnailBytes(reference);
          }
        }
      } else {
        final legacyImageCount = item.imagePaths.where((path) {
          final trimmed = path.trim();
          return trimmed.isNotEmpty && _looksLikeRemotePath(trimmed);
        }).length;
        if (legacyImageCount > 0) {
          totalImageCount += legacyImageCount;
          totalStoredBytes += legacyImageCount * targetFullImageBytes;
          debugPrint(
            '[IkeepQuota] byte estimate fallback '
            'scope=$scope item=${item.uuid} legacyImages=$legacyImageCount',
          );
        }
      }

      if (invoiceRef != null) {
        if (pdfPaths.add(invoiceRef.storagePath)) {
          totalPdfCount++;
        }
        if (storedPaths.add(invoiceRef.storagePath)) {
          totalStoredBytes += _storedBytesForInvoice(
            reference: invoiceRef,
            fallbackItem: item,
            scope: scope,
          );
        }
      } else {
        final legacyInvoicePath = item.invoicePath?.trim();
        if (legacyInvoicePath != null &&
            legacyInvoicePath.isNotEmpty &&
            _looksLikeRemotePath(legacyInvoicePath)) {
          totalPdfCount++;
          totalStoredBytes += item.invoiceFileSizeBytes ?? 0;
          debugPrint(
            '[IkeepQuota] byte estimate fallback '
            'scope=$scope item=${item.uuid} legacyInvoice=true '
            'bytes=${item.invoiceFileSizeBytes ?? 0}',
          );
        }
      }
    }

    return CloudUsageSnapshot(
      scope: scope,
      householdId: householdId,
      planMode: planMode,
      backedUpItemCount: items.length,
      totalImageCount: totalImageCount,
      totalPdfCount: totalPdfCount,
      totalStoredBytes: totalStoredBytes,
      householdMemberCount: householdMemberCount,
      updatedAt: DateTime.now(),
    );
  }

  Future<_ItemCloudContribution> _existingContributionForItem(Item item) async {
    final itemReferences = await _itemCloudMediaDao.getReferencesForItem(item.uuid);
    if (itemReferences.isNotEmpty) {
      return _ItemCloudContribution(
        isTrackedItem: true,
      );
    }

    if (!_hasCloudIdentity(item)) {
      return const _ItemCloudContribution(
        isTrackedItem: false,
      );
    }

    return _ItemCloudContribution(
      isTrackedItem: true,
    );
  }

  int _storedBytesForImage(ItemCloudMediaReference reference) {
    final byteSize = reference.byteSize;
    if (byteSize != null && byteSize > 0) {
      return byteSize;
    }
    debugPrint(
      '[IkeepQuota] byte estimate fallback '
      'storagePath=${reference.storagePath} kind=image_full '
      'estimated=$targetFullImageBytes',
    );
    return targetFullImageBytes;
  }

  int _estimatedThumbnailBytes(ItemCloudMediaReference reference) {
    debugPrint(
      '[IkeepQuota] byte estimate fallback '
      'storagePath=${reference.thumbnailPath ?? reference.storagePath} '
      'kind=image_thumb estimated=$targetThumbnailBytes',
    );
    return targetThumbnailBytes;
  }

  int _storedBytesForInvoice({
    required ItemCloudMediaReference reference,
    required Item fallbackItem,
    required String scope,
  }) {
    final byteSize = reference.byteSize;
    if (byteSize != null && byteSize > 0) {
      return byteSize;
    }
    final fallbackSize = fallbackItem.invoiceFileSizeBytes ?? 0;
    debugPrint(
      '[IkeepQuota] byte estimate fallback '
      'scope=$scope item=${fallbackItem.uuid} storagePath=${reference.storagePath} '
      'kind=invoice estimated=$fallbackSize',
    );
    return fallbackSize;
  }

  bool _isCloudTrackedItem(Item item) {
    return _hasCloudIdentity(item) &&
        (item.isBackedUp || item.visibility.isHousehold);
  }

  bool _hasCloudIdentity(Item item) {
    return (item.cloudId?.trim().isNotEmpty ?? false) || item.lastSyncedAt != null;
  }

  bool _looksLikeRemotePath(String path) {
    final normalized = path.toLowerCase();
    return normalized.startsWith('http://') ||
        normalized.startsWith('https://') ||
        normalized.startsWith('gs://') ||
        normalized.startsWith('users/');
  }

  void _logUsageSnapshot(String action, CloudUsageSnapshot snapshot) {
    debugPrint(
      '[IkeepQuota] usage $action scope=${snapshot.scope} '
      'mode=${snapshot.planMode.storageValue} '
      'items=${snapshot.backedUpItemCount} '
      'images=${snapshot.totalImageCount} '
      'pdfs=${snapshot.totalPdfCount} '
      'bytes=${snapshot.totalStoredBytes} '
      'members=${snapshot.householdMemberCount}',
    );
  }

  void _logEvaluation(String action, CloudQuotaEvaluation evaluation) {
    debugPrint(
      '[IkeepQuota] evaluation action=$action scope=${evaluation.scope} '
      'mode=${evaluation.planMode.storageValue} '
      'allowedNow=${evaluation.allowedNow} '
      'wouldBlockInPaidMode=${evaluation.wouldBlockInPaidMode} '
      'reason=${evaluation.reasonCode.name} '
      'usage=${evaluation.currentUsage}/${evaluation.futureLimit}',
    );
  }
}

class _ItemCloudContribution {
  const _ItemCloudContribution({
    required this.isTrackedItem,
  });

  final bool isTrackedItem;
}
