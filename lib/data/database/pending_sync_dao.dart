import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import 'database_helper.dart';

class PendingSyncOperation {
  const PendingSyncOperation({
    required this.id,
    required this.operationType,
    required this.entityType,
    required this.entityUuid,
    required this.payload,
    required this.failedAt,
  });

  final int id;
  final String operationType;
  final String entityType;
  final String entityUuid;
  final Map<String, dynamic> payload;
  final DateTime failedAt;

  factory PendingSyncOperation.fromMap(Map<String, dynamic> map) {
    return PendingSyncOperation(
      id: map[DbConstants.colSyncId] as int,
      operationType: map[DbConstants.colSyncOperationType] as String,
      entityType: map[DbConstants.colSyncEntityType] as String,
      entityUuid: map[DbConstants.colSyncEntityUuid] as String,
      payload: Map<String, dynamic>.from(
        jsonDecode(map[DbConstants.colSyncPayload] as String)
            as Map<dynamic, dynamic>,
      ),
      failedAt: DateTime.fromMillisecondsSinceEpoch(
        map[DbConstants.colSyncFailedAt] as int,
      ),
    );
  }
}

class PendingSyncEnqueueRequest {
  const PendingSyncEnqueueRequest({
    required this.operationType,
    required this.entityType,
    required this.entityUuid,
    required this.payload,
  });

  final String operationType;
  final String entityType;
  final String entityUuid;
  final Map<String, dynamic> payload;
}

class PendingSyncDao {
  const PendingSyncDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<void> enqueue({
    required String operationType,
    required String entityType,
    required String entityUuid,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        DbConstants.tablePendingSync,
        where:
            '${DbConstants.colSyncEntityType} = ? AND '
            '${DbConstants.colSyncEntityUuid} = ?',
        whereArgs: [entityType, entityUuid],
      );
      await txn.insert(
        DbConstants.tablePendingSync,
        {
          DbConstants.colSyncOperationType: operationType,
          DbConstants.colSyncEntityType: entityType,
          DbConstants.colSyncEntityUuid: entityUuid,
          DbConstants.colSyncPayload: jsonEncode(payload),
          DbConstants.colSyncFailedAt: DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> enqueueAllInTransaction(
    Transaction executor,
    Iterable<PendingSyncEnqueueRequest> requests,
  ) async {
    final batch = executor.batch();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final request in requests) {
      batch.delete(
        DbConstants.tablePendingSync,
        where:
            '${DbConstants.colSyncEntityType} = ? AND '
            '${DbConstants.colSyncEntityUuid} = ?',
        whereArgs: [request.entityType, request.entityUuid],
      );
      batch.insert(
        DbConstants.tablePendingSync,
        {
          DbConstants.colSyncOperationType: request.operationType,
          DbConstants.colSyncEntityType: request.entityType,
          DbConstants.colSyncEntityUuid: request.entityUuid,
          DbConstants.colSyncPayload: jsonEncode(request.payload),
          DbConstants.colSyncFailedAt: nowMs,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<PendingSyncOperation>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tablePendingSync,
      orderBy: '${DbConstants.colSyncFailedAt} ASC',
    );
    return rows.map(PendingSyncOperation.fromMap).toList();
  }

  Future<List<PendingSyncOperation>> getByEntityType(String entityType) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tablePendingSync,
      where: '${DbConstants.colSyncEntityType} = ?',
      whereArgs: [entityType],
      orderBy: '${DbConstants.colSyncFailedAt} ASC',
    );
    return rows.map(PendingSyncOperation.fromMap).toList();
  }

  Future<void> deleteById(int id) async {
    final db = await _db;
    await db.delete(
      DbConstants.tablePendingSync,
      where: '${DbConstants.colSyncId} = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteByEntity({
    required String entityType,
    required String entityUuid,
  }) async {
    final db = await _db;
    await db.delete(
      DbConstants.tablePendingSync,
      where:
          '${DbConstants.colSyncEntityType} = ? AND '
          '${DbConstants.colSyncEntityUuid} = ?',
      whereArgs: [entityType, entityUuid],
    );
  }

  Future<void> deleteByEntityType(String entityType) async {
    final db = await _db;
    await db.delete(
      DbConstants.tablePendingSync,
      where: '${DbConstants.colSyncEntityType} = ?',
      whereArgs: [entityType],
    );
  }
}
