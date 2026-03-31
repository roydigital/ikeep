import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/item.dart';
import 'database_helper.dart';

/// Data Access Object for the [items] table.
class ItemDao {
  const ItemDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<void> insertItem(Item item) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableItems,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertItemsInTransaction(
    Transaction executor,
    Iterable<Item> items,
  ) async {
    final batch = executor.batch();
    for (final item in items) {
      batch.insert(
        DbConstants.tableItems,
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateItem(Item item) async {
    final db = await _db;
    await db.update(
      DbConstants.tableItems,
      item.toMap(),
      where: '${DbConstants.colItemUuid} = ?',
      whereArgs: [item.uuid],
    );
  }

  Future<void> deleteItem(String uuid) async {
    final db = await _db;
    await db.delete(
      DbConstants.tableItems,
      where: '${DbConstants.colItemUuid} = ?',
      whereArgs: [uuid],
    );
  }

  Future<Item?> getItemByUuid(String uuid) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      WHERE i.${DbConstants.colItemUuid} = ?
      LIMIT 1
    ''', [uuid]);
    if (rows.isEmpty) return null;
    return Item.fromMap(rows.first);
  }

  /// Returns all backed-up items regardless of archived state, newest first.
  ///
  /// Used by [FirebaseSyncService.fullSync] so that archived items are pushed
  /// to Firestore and their archived state stays in sync across devices/installs.
  Future<List<Item>> getAllBackedUpItems() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      WHERE i.${DbConstants.colItemIsBackedUp} = 1
      ORDER BY i.${DbConstants.colItemSavedAt} DESC
    ''');
    return rows.map(Item.fromMap).toList();
  }

  /// Returns items, newest first, with location join.
  ///
  /// [includeArchived] defaults to false (home screen behaviour). Pass true
  /// to include archived items — used by [FirebaseSyncService.fullSync] so
  /// that archived items are pushed/pulled and their state stays consistent
  /// across devices and reinstalls.
  Future<List<Item>> getAllItems({int? limit, bool includeArchived = false}) async {
    final db = await _db;
    final archivedClause =
        includeArchived ? '' : 'WHERE i.${DbConstants.colItemIsArchived} = 0';
    final rows = await db.rawQuery('''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      $archivedClause
      ORDER BY i.${DbConstants.colItemSavedAt} DESC
      ${limit != null ? 'LIMIT $limit' : ''}
    ''');
    return rows.map(Item.fromMap).toList();
  }

  Future<List<Item>> getArchivedItems() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      WHERE i.${DbConstants.colItemIsArchived} = 1
      ORDER BY i.${DbConstants.colItemSavedAt} DESC
    ''');
    return rows.map(Item.fromMap).toList();
  }

  Future<List<Item>> getItemsPage({
    required int limit,
    required int offset,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      WHERE i.${DbConstants.colItemIsArchived} = 0
      ORDER BY i.${DbConstants.colItemSavedAt} DESC
      LIMIT ? OFFSET ?
    ''', [limit, offset]);
    return rows.map(Item.fromMap).toList();
  }

  Future<List<String>> getAllTags() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableItems,
      columns: [DbConstants.colItemTags],
      where: '${DbConstants.colItemIsArchived} = 0',
    );

    final tags = <String>{};
    for (final row in rows) {
      final rawTags = row[DbConstants.colItemTags] as String? ?? '[]';
      final decoded = jsonDecode(rawTags) as List<dynamic>;
      for (final tag in decoded.cast<String>()) {
        final normalized = tag.trim();
        if (normalized.isNotEmpty) {
          tags.add(normalized);
        }
      }
    }

    final sorted = tags.toList()..sort();
    return sorted;
  }

  Future<int> countBackedUpItems() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS count
      FROM ${DbConstants.tableItems}
      WHERE ${DbConstants.colItemIsBackedUp} = 1
    ''');
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<List<Item>> getSharedItems({String? householdId}) async {
    final db = await _db;
    final whereClause = householdId == null || householdId.isEmpty
        ? '''
      WHERE i.${DbConstants.colItemIsArchived} = 0
        AND i.${DbConstants.colItemVisibility} = 'household'
    '''
        : '''
      WHERE i.${DbConstants.colItemIsArchived} = 0
        AND i.${DbConstants.colItemVisibility} = 'household'
        AND i.${DbConstants.colItemHouseholdId} = ?
    ''';

    final rows = await db.rawQuery(
      '''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      $whereClause
      ORDER BY COALESCE(i.${DbConstants.colItemUpdatedAt}, i.${DbConstants.colItemSavedAt}) DESC
    ''',
      householdId == null || householdId.isEmpty ? null : [householdId],
    );
    return rows.map(Item.fromMap).toList();
  }

  Future<List<Item>> getItemsByLocation(String locationUuid) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      WHERE i.${DbConstants.colItemLocationUuid} = ?
        AND i.${DbConstants.colItemIsArchived} = 0
      ORDER BY i.${DbConstants.colItemSavedAt} DESC
    ''', [locationUuid]);
    return rows.map(Item.fromMap).toList();
  }

  /// SQL LIKE search across name, tags, and notes. Results are then fuzzy-ranked
  /// by the repository layer.
  Future<List<Item>> searchItems(String query) async {
    final db = await _db;
    final like = '%${query.toLowerCase()}%';
    final rows = await db.rawQuery('''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      WHERE i.${DbConstants.colItemIsArchived} = 0
        AND (
          LOWER(i.${DbConstants.colItemName}) LIKE ?
          OR LOWER(i.${DbConstants.colItemTags}) LIKE ?
          OR LOWER(i.${DbConstants.colItemNotes}) LIKE ?
          OR LOWER(l.name) LIKE ?
          OR LOWER(l.full_path) LIKE ?
        )
      ORDER BY i.${DbConstants.colItemSavedAt} DESC
    ''', [like, like, like, like, like]);
    return rows.map(Item.fromMap).toList();
  }

  /// Returns items with expiry dates that have not been archived.
  Future<List<Item>> getItemsWithExpiry() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      WHERE i.${DbConstants.colItemExpiryDate} IS NOT NULL
        AND i.${DbConstants.colItemIsArchived} = 0
    ''');
    return rows.map(Item.fromMap).toList();
  }

  Future<Item?> getRandomStaleItem({
    required DateTime cutoff,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      WHERE COALESCE(
        i.${DbConstants.colItemUpdatedAt},
        i.${DbConstants.colItemSavedAt}
      ) < ?
        AND i.${DbConstants.colItemIsArchived} = 0
      ORDER BY RANDOM()
      LIMIT 1
    ''', [cutoff.millisecondsSinceEpoch]);
    if (rows.isEmpty) return null;
    return Item.fromMap(rows.first);
  }

  Future<Item?> getRandomItemBySeasonCategories(
    List<String> seasonCategories,
  ) async {
    if (seasonCategories.isEmpty) return null;

    final db = await _db;
    final placeholders = List.filled(seasonCategories.length, '?').join(', ');
    final rows = await db.rawQuery('''
      SELECT i.*, l.name AS location_name, l.full_path AS location_full_path
      FROM ${DbConstants.tableItems} i
      LEFT JOIN ${DbConstants.tableLocations} l
        ON i.${DbConstants.colItemLocationUuid} = l.${DbConstants.colLocUuid}
      WHERE i.${DbConstants.colItemSeasonCategory} IN ($placeholders)
        AND i.${DbConstants.colItemIsArchived} = 0
      ORDER BY RANDOM()
      LIMIT 1
    ''', seasonCategories);
    if (rows.isEmpty) return null;
    return Item.fromMap(rows.first);
  }
}
