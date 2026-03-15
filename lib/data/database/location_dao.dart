import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/location_model.dart';
import 'database_helper.dart';

/// Data Access Object for the [locations] table.
class LocationDao {
  const LocationDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<void> insertLocation(LocationModel location) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableLocations,
      location.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateLocation(LocationModel location) async {
    final db = await _db;
    await db.update(
      DbConstants.tableLocations,
      location.toMap(),
      where: '${DbConstants.colLocUuid} = ?',
      whereArgs: [location.uuid],
    );
  }

  Future<void> deleteLocation(String uuid) async {
    final db = await _db;
    // Children cascade via FK ON DELETE CASCADE.
    await db.delete(
      DbConstants.tableLocations,
      where: '${DbConstants.colLocUuid} = ?',
      whereArgs: [uuid],
    );
  }

  Future<LocationModel?> getLocationByUuid(String uuid) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableLocations,
      where: '${DbConstants.colLocUuid} = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocationModel.fromMap(rows.first);
  }

  Future<List<LocationModel>> getAllLocations() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableLocations,
      orderBy: '${DbConstants.colLocUsageCount} DESC, ${DbConstants.colLocName} ASC',
    );
    return rows.map(LocationModel.fromMap).toList();
  }

  Future<List<LocationModel>> getRootLocations() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableLocations,
      where: '${DbConstants.colLocParentUuid} IS NULL',
      orderBy: '${DbConstants.colLocUsageCount} DESC, ${DbConstants.colLocName} ASC',
    );
    return rows.map(LocationModel.fromMap).toList();
  }

  Future<List<LocationModel>> getChildLocations(String parentUuid) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableLocations,
      where: '${DbConstants.colLocParentUuid} = ?',
      whereArgs: [parentUuid],
      orderBy: '${DbConstants.colLocName} ASC',
    );
    return rows.map(LocationModel.fromMap).toList();
  }

  Future<void> incrementUsageCount(String uuid) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE ${DbConstants.tableLocations}
      SET ${DbConstants.colLocUsageCount} = ${DbConstants.colLocUsageCount} + 1
      WHERE ${DbConstants.colLocUuid} = ?
    ''', [uuid]);
  }

  /// Returns the ordered ancestor chain for a location (from root to parent).
  Future<List<LocationModel>> getAncestors(String uuid) async {
    final ancestors = <LocationModel>[];
    String? current = uuid;
    final db = await _db;

    while (current != null) {
      final rows = await db.query(
        DbConstants.tableLocations,
        where: '${DbConstants.colLocUuid} = ?',
        whereArgs: [current],
        limit: 1,
      );
      if (rows.isEmpty) break;
      final loc = LocationModel.fromMap(rows.first);
      ancestors.insert(0, loc);
      current = loc.parentUuid;
    }
    return ancestors;
  }
}
