import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/cloud_usage_snapshot.dart';
import 'database_helper.dart';

class CloudUsageSnapshotDao {
  const CloudUsageSnapshotDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<CloudUsageSnapshot?> getByScope(String scope) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableCloudUsageSnapshots,
      where: '${DbConstants.colCloudUsageScope} = ?',
      whereArgs: [scope],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return CloudUsageSnapshot.fromMap(rows.first);
  }

  Future<void> upsert(CloudUsageSnapshot snapshot) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableCloudUsageSnapshots,
      snapshot.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CloudUsageSnapshot>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableCloudUsageSnapshots,
      orderBy: '${DbConstants.colCloudUsageUpdatedAt} DESC',
    );
    return rows.map(CloudUsageSnapshot.fromMap).toList(growable: false);
  }
}
