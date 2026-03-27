import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/household_member.dart';
import 'database_helper.dart';

class HouseholdMemberDao {
  const HouseholdMemberDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<void> insertMember(HouseholdMember member) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableHouseholdMembers,
      member.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<HouseholdMember>> getAllMembers() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableHouseholdMembers,
      orderBy:
          '${DbConstants.colMemberIsOwner} DESC, ${DbConstants.colMemberInvitedAt} ASC',
    );
    return rows.map(HouseholdMember.fromMap).toList();
  }

  Future<int> countMembersForHousehold(String householdId) async {
    final db = await _db;
    final trimmedHouseholdId = householdId.trim();
    if (trimmedHouseholdId.isEmpty) {
      return 0;
    }

    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${DbConstants.tableHouseholdMembers}
      WHERE ${DbConstants.colMemberHouseholdUuid} = ?
      ''',
      [trimmedHouseholdId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<void> replaceAllMembers(List<HouseholdMember> members) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(DbConstants.tableHouseholdMembers);
      for (final member in members) {
        await txn.insert(
          DbConstants.tableHouseholdMembers,
          member.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> ensureOwnerMember() async {
    final db = await _db;
    await db.insert(
      DbConstants.tableHouseholdMembers,
      {
        DbConstants.colMemberUuid: 'owner-local',
        DbConstants.colMemberName: 'You',
        DbConstants.colMemberInvitedAt: DateTime.now().millisecondsSinceEpoch,
        DbConstants.colMemberIsOwner: 1,
        DbConstants.colMemberJoinedAt: DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
