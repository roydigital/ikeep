import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/failure.dart';
import '../../domain/models/item_location_history.dart';
import '../database/history_dao.dart';
import '../../services/household_cloud_service.dart';
import 'history_repository.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl({
    required this.historyDao,
    required this.householdCloudService,
  });

  final HistoryDao historyDao;
  final HouseholdCloudService householdCloudService;

  @override
  Future<Failure?> recordMove(ItemLocationHistory entry) async {
    try {
      await historyDao.insertHistory(entry);
      await _syncHistoryIfShared(entry);
      return null;
    } on FirebaseException catch (e) {
      return Failure(e.message ?? 'Failed to sync history: ${e.code}', e);
    } catch (e) {
      return Failure('Failed to record move', e);
    }
  }

  @override
  Future<Failure?> upsertHistory(ItemLocationHistory entry) async {
    try {
      await historyDao.upsertHistory(entry);
      await _syncHistoryIfShared(entry);
      return null;
    } on FirebaseException catch (e) {
      return Failure(e.message ?? 'Failed to sync history: ${e.code}', e);
    } catch (e) {
      return Failure('Failed to upsert move history', e);
    }
  }

  @override
  Future<List<ItemLocationHistory>> getHistoryForItem(String itemUuid) =>
      historyDao.getHistoryForItem(itemUuid);

  @override
  Future<ItemLocationHistory?> getLatestHistoryForItem(String itemUuid) =>
      historyDao.getLatestHistoryForItem(itemUuid);

  Future<void> _syncHistoryIfShared(ItemLocationHistory entry) async {
    final householdId = entry.householdId;
    if (householdId == null || householdId.isEmpty) return;

    await householdCloudService.syncItemHistory(
      householdId: householdId,
      history: entry,
    );
  }
}
