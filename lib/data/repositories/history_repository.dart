import '../../core/errors/failure.dart';
import '../../domain/models/item_location_history.dart';

abstract class HistoryRepository {
  Future<Failure?> recordMove(ItemLocationHistory entry);
  Future<Failure?> upsertHistory(ItemLocationHistory entry);
  Future<List<ItemLocationHistory>> getHistoryForItem(String itemUuid);
  Future<ItemLocationHistory?> getLatestHistoryForItem(String itemUuid);
}
