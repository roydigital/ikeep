import '../../core/errors/app_exception.dart';
import '../../core/errors/failure.dart';
import '../../core/utils/uuid_generator.dart';
import '../../domain/models/item.dart';
import '../../domain/models/item_location_history.dart';
import '../database/history_dao.dart';
import '../database/item_dao.dart';
import '../database/location_dao.dart';
import 'item_repository.dart';

class ItemRepositoryImpl implements ItemRepository {
  ItemRepositoryImpl({
    required this.itemDao,
    required this.locationDao,
    required this.historyDao,
  });

  final ItemDao itemDao;
  final LocationDao locationDao;
  final HistoryDao historyDao;

  @override
  Future<Failure?> saveItem(Item item) async {
    try {
      await itemDao.insertItem(item);

      // Record initial placement in history
      if (item.locationUuid != null) {
        final loc = await locationDao.getLocationByUuid(item.locationUuid!);
        await historyDao.insertHistory(ItemLocationHistory(
          uuid: generateUuid(),
          itemUuid: item.uuid,
          locationUuid: item.locationUuid,
          locationName: loc?.name ?? item.locationUuid!,
          movedAt: item.savedAt,
        ));
        await locationDao.incrementUsageCount(item.locationUuid!);
      }
      return null;
    } on DatabaseException catch (e) {
      return Failure.fromException(e);
    } catch (e) {
      return Failure('Failed to save item', e);
    }
  }

  @override
  Future<Failure?> updateItem(Item item) async {
    try {
      final existing = await itemDao.getItemByUuid(item.uuid);
      final locationChanged = existing?.locationUuid != item.locationUuid;

      final updated = item.copyWith(updatedAt: DateTime.now());
      await itemDao.updateItem(updated);

      // Record location change in history
      if (locationChanged && item.locationUuid != null) {
        final loc = await locationDao.getLocationByUuid(item.locationUuid!);
        await historyDao.insertHistory(ItemLocationHistory(
          uuid: generateUuid(),
          itemUuid: item.uuid,
          locationUuid: item.locationUuid,
          locationName: loc?.name ?? item.locationUuid!,
          movedAt: DateTime.now(),
        ));
        await locationDao.incrementUsageCount(item.locationUuid!);
      }
      return null;
    } on DatabaseException catch (e) {
      return Failure.fromException(e);
    } catch (e) {
      return Failure('Failed to update item', e);
    }
  }

  @override
  Future<Failure?> archiveItem(String uuid) async {
    try {
      final item = await itemDao.getItemByUuid(uuid);
      if (item == null) return Failure('Item not found: $uuid');
      await itemDao.updateItem(
        item.copyWith(isArchived: true, updatedAt: DateTime.now()),
      );
      return null;
    } catch (e) {
      return Failure('Failed to archive item', e);
    }
  }

  @override
  Future<Failure?> deleteItem(String uuid) async {
    try {
      await historyDao.deleteHistoryForItem(uuid);
      await itemDao.deleteItem(uuid);
      return null;
    } catch (e) {
      return Failure('Failed to delete item', e);
    }
  }

  @override
  Future<Item?> getItem(String uuid) => itemDao.getItemByUuid(uuid);

  @override
  Future<List<Item>> getAllItems() => itemDao.getAllItems();

  @override
  Future<List<Item>> getItemsByLocation(String locationUuid) =>
      itemDao.getItemsByLocation(locationUuid);

  @override
  Future<List<Item>> searchItems(String query) async {
    if (query.trim().isEmpty) return getAllItems();
    return itemDao.searchItems(query);
  }

  @override
  Future<List<Item>> getArchivedItems() => itemDao.getArchivedItems();
}
