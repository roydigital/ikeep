import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/item_cloud_media_reference.dart';
import 'database_helper.dart';

class ItemCloudMediaDao {
  const ItemCloudMediaDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<void> replaceForItem({
    required String itemUuid,
    required List<ItemCloudMediaReference> references,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        DbConstants.tableItemCloudMedia,
        where: '${DbConstants.colItemCloudMediaItemUuid} = ?',
        whereArgs: [itemUuid],
      );

      for (final reference in references) {
        await txn.insert(
          DbConstants.tableItemCloudMedia,
          reference.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<ItemCloudMediaReference?> getImageReference({
    required String itemUuid,
    required int slotIndex,
  }) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableItemCloudMedia,
      where:
          '${DbConstants.colItemCloudMediaItemUuid} = ? AND ${DbConstants.colItemCloudMediaRole} = ? AND ${DbConstants.colItemCloudMediaSlotIndex} = ?',
      whereArgs: [itemUuid, ItemCloudMediaRole.image.dbValue, slotIndex],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ItemCloudMediaReference.fromMap(rows.first);
  }

  Future<List<ItemCloudMediaReference>> getReferencesForItem(
    String itemUuid,
  ) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableItemCloudMedia,
      where: '${DbConstants.colItemCloudMediaItemUuid} = ?',
      whereArgs: [itemUuid],
      orderBy:
          '${DbConstants.colItemCloudMediaRole} ASC, ${DbConstants.colItemCloudMediaSlotIndex} ASC',
    );
    return rows.map(ItemCloudMediaReference.fromMap).toList();
  }

  Future<List<ItemCloudMediaReference>> getAllReferences() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableItemCloudMedia,
      orderBy:
          '${DbConstants.colItemCloudMediaItemUuid} ASC, ${DbConstants.colItemCloudMediaRole} ASC, ${DbConstants.colItemCloudMediaSlotIndex} ASC',
    );
    return rows.map(ItemCloudMediaReference.fromMap).toList(growable: false);
  }

  Future<ItemCloudMediaReference?> getInvoiceReference(String itemUuid) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableItemCloudMedia,
      where:
          '${DbConstants.colItemCloudMediaItemUuid} = ? AND ${DbConstants.colItemCloudMediaRole} = ?',
      whereArgs: [itemUuid, ItemCloudMediaRole.invoice.dbValue],
      orderBy: '${DbConstants.colItemCloudMediaSlotIndex} ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ItemCloudMediaReference.fromMap(rows.first);
  }

  Future<void> deleteForItem(String itemUuid) async {
    final db = await _db;
    await db.delete(
      DbConstants.tableItemCloudMedia,
      where: '${DbConstants.colItemCloudMediaItemUuid} = ?',
      whereArgs: [itemUuid],
    );
  }
}
