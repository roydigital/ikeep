import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/cloud_media_observation_activity.dart';
import '../../domain/models/cloud_observation_metrics.dart';
import 'database_helper.dart';

class CloudObservationDao {
  const CloudObservationDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<CloudObservationMetrics?> getMetrics(String scope) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableCloudObservationMetrics,
      where: '${DbConstants.colCloudObservationScope} = ?',
      whereArgs: [scope],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return CloudObservationMetrics.fromMap(rows.first);
  }

  Future<void> upsertMetrics(CloudObservationMetrics metrics) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableCloudObservationMetrics,
      metrics.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CloudMediaObservationActivity?> getMediaActivity(
    String activityKey,
  ) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableCloudMediaObservation,
      where: '${DbConstants.colCloudMediaObservationKey} = ?',
      whereArgs: [activityKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return CloudMediaObservationActivity.fromMap(rows.first);
  }

  Future<void> upsertMediaActivity(
    CloudMediaObservationActivity activity,
  ) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableCloudMediaObservation,
      activity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CloudMediaObservationActivity>> getAllMediaActivities() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableCloudMediaObservation,
      orderBy:
          '${DbConstants.colCloudMediaObservationLastDownloadedAt} DESC',
    );
    return rows
        .map(CloudMediaObservationActivity.fromMap)
        .toList(growable: false);
  }
}
