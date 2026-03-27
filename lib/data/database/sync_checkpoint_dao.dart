import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/sync_checkpoint_state.dart';
import 'database_helper.dart';

class SyncCheckpointDao {
  const SyncCheckpointDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<SyncCheckpointState?> getByScope(String syncScope) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableSyncCheckpoints,
      where: '${DbConstants.colSyncCheckpointScope} = ?',
      whereArgs: [syncScope],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return SyncCheckpointState.fromMap(rows.first);
  }

  Future<void> upsert(SyncCheckpointState checkpoint) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableSyncCheckpoints,
      checkpoint.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteByScope(String syncScope) async {
    final db = await _db;
    await db.delete(
      DbConstants.tableSyncCheckpoints,
      where: '${DbConstants.colSyncCheckpointScope} = ?',
      whereArgs: [syncScope],
    );
  }

  Future<List<SyncCheckpointState>> getByHouseholdId(String householdId) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableSyncCheckpoints,
      where: '${DbConstants.colSyncCheckpointHouseholdId} = ?',
      whereArgs: [householdId],
      orderBy: '${DbConstants.colSyncCheckpointUpdatedAt} DESC',
    );
    return rows.map(SyncCheckpointState.fromMap).toList(growable: false);
  }

  Future<List<SyncCheckpointState>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableSyncCheckpoints,
      orderBy: '${DbConstants.colSyncCheckpointUpdatedAt} DESC',
    );
    return rows.map(SyncCheckpointState.fromMap).toList(growable: false);
  }
}
