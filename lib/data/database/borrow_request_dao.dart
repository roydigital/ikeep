import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/borrow_request.dart';
import 'database_helper.dart';

class BorrowRequestDao {
  const BorrowRequestDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<void> insertRequest(BorrowRequest request) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableBorrowRequests,
      request.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateRequest(BorrowRequest request) async {
    final db = await _db;
    await db.update(
      DbConstants.tableBorrowRequests,
      request.toMap(),
      where: '${DbConstants.colBorrowRequestUuid} = ?',
      whereArgs: [request.uuid],
    );
  }

  Future<BorrowRequest?> getRequestByUuid(String uuid) async {
    final db = await _db;
    final rows = await db.rawQuery(
      _baseQuery(
        whereClause: 'WHERE r.${DbConstants.colBorrowRequestUuid} = ? LIMIT 1',
      ),
      [uuid],
    );
    if (rows.isEmpty) return null;
    return BorrowRequest.fromMap(rows.first);
  }

  Future<List<BorrowRequest>> getRequestsForOwner(
    String ownerMemberUuid, {
    List<BorrowRequestStatus>? statuses,
  }) async {
    final db = await _db;
    final args = <Object?>[ownerMemberUuid];
    final where = StringBuffer(
      'WHERE r.${DbConstants.colBorrowOwnerMemberUuid} = ?',
    );
    _appendStatuses(where, args, statuses);

    final rows = await db.rawQuery(
      _baseQuery(
        whereClause:
            '$where ORDER BY r.${DbConstants.colBorrowRequestedAt} DESC',
      ),
      args,
    );
    return rows.map(BorrowRequest.fromMap).toList();
  }

  Future<List<BorrowRequest>> getRequestsForRequester(
    String requesterMemberUuid, {
    List<BorrowRequestStatus>? statuses,
  }) async {
    final db = await _db;
    final args = <Object?>[requesterMemberUuid];
    final where = StringBuffer(
      'WHERE r.${DbConstants.colBorrowRequesterMemberUuid} = ?',
    );
    _appendStatuses(where, args, statuses);

    final rows = await db.rawQuery(
      _baseQuery(
        whereClause:
            '$where ORDER BY r.${DbConstants.colBorrowRequestedAt} DESC',
      ),
      args,
    );
    return rows.map(BorrowRequest.fromMap).toList();
  }

  Future<List<BorrowRequest>> getRequestsForItem(String itemUuid) async {
    final db = await _db;
    final rows = await db.rawQuery(
      _baseQuery(
        whereClause:
            'WHERE r.${DbConstants.colBorrowItemUuid} = ? ORDER BY r.${DbConstants.colBorrowRequestedAt} DESC',
      ),
      [itemUuid],
    );
    return rows.map(BorrowRequest.fromMap).toList();
  }

  Future<BorrowRequest?> getPendingRequestForItemByRequester(
    String itemUuid,
    String requesterMemberUuid,
  ) async {
    final db = await _db;
    final rows = await db.rawQuery(
      _baseQuery(
        whereClause: '''
          WHERE r.${DbConstants.colBorrowItemUuid} = ?
            AND r.${DbConstants.colBorrowRequesterMemberUuid} = ?
            AND r.${DbConstants.colBorrowStatus} = ?
          ORDER BY r.${DbConstants.colBorrowRequestedAt} DESC
          LIMIT 1
        ''',
      ),
      [itemUuid, requesterMemberUuid, BorrowRequestStatus.pending.value],
    );
    if (rows.isEmpty) return null;
    return BorrowRequest.fromMap(rows.first);
  }

  Future<void> resolvePendingRequestsForItem(
    String itemUuid, {
    required BorrowRequestStatus status,
    required DateTime respondedAt,
    String? exceptRequestUuid,
    String? note,
  }) async {
    final db = await _db;
    final whereBuffer = StringBuffer(
      '${DbConstants.colBorrowItemUuid} = ? AND ${DbConstants.colBorrowStatus} = ?',
    );
    final args = <Object?>[itemUuid, BorrowRequestStatus.pending.value];
    if (exceptRequestUuid != null) {
      whereBuffer.write(' AND ${DbConstants.colBorrowRequestUuid} != ?');
      args.add(exceptRequestUuid);
    }

    await db.update(
      DbConstants.tableBorrowRequests,
      {
        DbConstants.colBorrowStatus: status.value,
        DbConstants.colBorrowRespondedAt: respondedAt.millisecondsSinceEpoch,
        if (note != null) DbConstants.colBorrowNote: note,
      },
      where: whereBuffer.toString(),
      whereArgs: args,
    );
  }

  String _baseQuery({required String whereClause}) {
    return '''
      SELECT
        r.*, 
        i.${DbConstants.colItemName} AS item_name,
        i.${DbConstants.colItemImagePaths} AS item_image_paths,
        i.${DbConstants.colItemIsLent} AS item_is_lent,
        i.${DbConstants.colItemIsAvailableForLending} AS item_is_available_for_lending
      FROM ${DbConstants.tableBorrowRequests} r
      INNER JOIN ${DbConstants.tableItems} i
        ON r.${DbConstants.colBorrowItemUuid} = i.${DbConstants.colItemUuid}
      $whereClause
    ''';
  }

  void _appendStatuses(
    StringBuffer where,
    List<Object?> args,
    List<BorrowRequestStatus>? statuses,
  ) {
    if (statuses == null || statuses.isEmpty) return;
    final placeholders = List.filled(statuses.length, '?').join(', ');
    where.write(' AND r.${DbConstants.colBorrowStatus} IN ($placeholders)');
    args.addAll(statuses.map((status) => status.value));
  }
}
