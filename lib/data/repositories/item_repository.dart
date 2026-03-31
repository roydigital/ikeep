import '../../core/errors/failure.dart';
import '../../domain/models/item.dart';

/// Abstract contract for item persistence. Concrete impl coordinates SQLite as
/// the source of truth, optional household cloud mirroring, and history writes.
abstract class ItemRepository {
  /// Saves a brand new item. Also records the initial location in history.
  Future<Failure?> saveItem(
    Item item, {
    String? movedByMemberUuid,
    String? movedByName,
  });

  /// Saves multiple brand new items in one local transaction.
  Future<SaveItemsBatchResult> saveItemsBatch(
    List<Item> items, {
    String? movedByMemberUuid,
    String? movedByName,
  });

  /// Updates an existing item. If location changed, records it in history
  /// and updates the old location's usage count.
  Future<Failure?> updateItem(
    Item item, {
    String? movedByMemberUuid,
    String? movedByName,
  });

  /// Soft-deletes an item by setting [isArchived] = true.
  Future<Failure?> archiveItem(String uuid);

  /// Hard-deletes an item and its history entries.
  Future<Failure?> deleteItem(String uuid);

  Future<Item?> getItem(String uuid);

  Future<List<Item>> getAllItems({int? limit});

  Future<List<Item>> getItemsPage({
    required int limit,
    required int offset,
  });

  Future<List<Item>> getItemsByLocation(String locationUuid);

  Future<List<Item>> getSharedItems({String? householdId});

  Future<List<Item>> searchItems(String query);

  Future<List<Item>> getArchivedItems();
}

class SaveItemsBatchResult {
  const SaveItemsBatchResult({
    required this.savedItems,
    this.failure,
  });

  final List<Item> savedItems;
  final Failure? failure;

  bool get hasFailure => failure != null;
}
