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

  /// Inserts a placeholder owner row only when no owner record exists yet.
  /// Used as a fallback when household creation cannot resolve the
  /// authenticated user (e.g. offline or anonymous flows).
  Future<void> ensureOwnerMember() async {
    final db = await _db;
    final existingOwners = await db.query(
      DbConstants.tableHouseholdMembers,
      where: '${DbConstants.colMemberIsOwner} = 1',
      limit: 1,
    );
    if (existingOwners.isNotEmpty) return;

    await db.insert(
      DbConstants.tableHouseholdMembers,
      {
        DbConstants.colMemberUuid: HouseholdMember.localOwnerUuid,
        DbConstants.colMemberName: HouseholdMember.localOwnerName,
        DbConstants.colMemberInvitedAt: DateTime.now().millisecondsSinceEpoch,
        DbConstants.colMemberIsOwner: 1,
        DbConstants.colMemberJoinedAt: DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Removes the legacy `owner-local` placeholder row if a real owner
  /// (with a Firebase UID) is also stored. Prevents duplicate "Owner" tiles
  /// in the Members list for users created before the real-owner insert was
  /// added to `createHousehold`.
  Future<void> removeLocalOwnerPlaceholderIfRealOwnerExists() async {
    final db = await _db;
    final realOwners = await db.query(
      DbConstants.tableHouseholdMembers,
      where:
          '${DbConstants.colMemberIsOwner} = 1 AND ${DbConstants.colMemberUuid} != ?',
      whereArgs: [HouseholdMember.localOwnerUuid],
      limit: 1,
    );
    if (realOwners.isEmpty) return;

    await db.delete(
      DbConstants.tableHouseholdMembers,
      where: '${DbConstants.colMemberUuid} = ?',
      whereArgs: [HouseholdMember.localOwnerUuid],
    );
  }
}
