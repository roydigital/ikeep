import '../../core/errors/failure.dart';
import '../../domain/models/item_location_history.dart';
import '../database/history_dao.dart';
import 'history_repository.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl({required this.historyDao});

  final HistoryDao historyDao;

  @override
  Future<Failure?> recordMove(ItemLocationHistory entry) async {
    try {
      await historyDao.insertHistory(entry);
      return null;
    } catch (e) {
      return Failure('Failed to record move', e);
    }
  }

  @override
  Future<List<ItemLocationHistory>> getHistoryForItem(String itemUuid) =>
      historyDao.getHistoryForItem(itemUuid);
}
