import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/media_cache_entry.dart';
import 'database_helper.dart';

class MediaCacheDao {
  const MediaCacheDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.db;

  Future<void> upsertEntry(MediaCacheEntry entry) async {
    final db = await _db;
    await db.insert(
      DbConstants.tableMediaCache,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<MediaCacheEntry?> getByCacheKey(String cacheKey) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableMediaCache,
      where: '${DbConstants.colMediaCacheKey} = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MediaCacheEntry.fromMap(rows.first);
  }

  Future<MediaCacheEntry?> getLatestByStoragePath({
    required String storagePath,
    required CachedMediaType mediaType,
  }) async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableMediaCache,
      where:
          '${DbConstants.colMediaStoragePath} = ? AND ${DbConstants.colMediaCacheType} = ?',
      whereArgs: [storagePath, mediaType.dbValue],
      orderBy: '${DbConstants.colMediaLastAccessedAt} DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MediaCacheEntry.fromMap(rows.first);
  }

  Future<List<MediaCacheEntry>> getAllEntries() async {
    final db = await _db;
    final rows = await db.query(
      DbConstants.tableMediaCache,
      orderBy: '${DbConstants.colMediaLastAccessedAt} DESC',
    );
    return rows.map(MediaCacheEntry.fromMap).toList();
  }

  Future<void> updateLastAccessedAt({
    required String cacheKey,
    required DateTime lastAccessedAt,
  }) async {
    final db = await _db;
    await db.update(
      DbConstants.tableMediaCache,
      {
        DbConstants.colMediaLastAccessedAt:
            lastAccessedAt.millisecondsSinceEpoch,
      },
      where: '${DbConstants.colMediaCacheKey} = ?',
      whereArgs: [cacheKey],
    );
  }

  Future<void> deleteByCacheKey(String cacheKey) async {
    final db = await _db;
    await db.delete(
      DbConstants.tableMediaCache,
      where: '${DbConstants.colMediaCacheKey} = ?',
      whereArgs: [cacheKey],
    );
  }
}
