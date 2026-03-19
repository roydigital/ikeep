import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/household.dart';
import 'database_helper.dart';

class HouseholdDao {
  const HouseholdDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<void> upsertHousehold(Household household) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableHouseholds,
      household.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Household?> getHouseholdById(String householdId) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableHouseholds,
      where: '${DbConstants.colHouseholdId} = ?',
      whereArgs: [householdId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Household.fromMap(rows.first);
  }

  Future<Household?> getLatestHousehold() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableHouseholds,
      orderBy: '${DbConstants.colHouseholdUpdatedAt} DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Household.fromMap(rows.first);
  }

  Future<void> deleteHousehold(String householdId) async {
    final db = await _db;
    await db.delete(
      DbConstants.tableHouseholds,
      where: '${DbConstants.colHouseholdId} = ?',
      whereArgs: [householdId],
    );
  }
}
