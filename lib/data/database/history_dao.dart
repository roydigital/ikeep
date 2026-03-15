import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/item_location_history.dart';
import 'database_helper.dart';

/// Data Access Object for [item_location_history]. Append-only — no updates.
class HistoryDao {
  const HistoryDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<void> insertHistory(ItemLocationHistory entry) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableHistory,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<ItemLocationHistory>> getHistoryForItem(String itemUuid) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableHistory,
      where: '${DbConstants.colHistItemUuid} = ?',
      whereArgs: [itemUuid],
      orderBy: '${DbConstants.colHistMovedAt} ASC',
    );
    return rows.map(ItemLocationHistory.fromMap).toList();
  }

  Future<void> deleteHistoryForItem(String itemUuid) async {
    final db = await _db;
    await db.delete(
      DbConstants.tableHistory,
      where: '${DbConstants.colHistItemUuid} = ?',
      whereArgs: [itemUuid],
    );
  }
}
