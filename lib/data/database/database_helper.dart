import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/constants/db_constants.dart';

/// Singleton that opens and owns the SQLite [Database].
/// All DAO classes receive this helper and call [db] to get the raw handle.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // Desktop platforms need the FFI factory.
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, DbConstants.dbName);

    return openDatabase(
      path,
      version: DbConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // Enable FK enforcement
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // ── items ──────────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE ${DbConstants.tableItems} (
        ${DbConstants.colItemId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colItemUuid} TEXT NOT NULL UNIQUE,
        ${DbConstants.colItemName} TEXT NOT NULL,
        ${DbConstants.colItemLocationUuid} TEXT,
        ${DbConstants.colItemImagePaths} TEXT NOT NULL DEFAULT '[]',
        ${DbConstants.colItemTags} TEXT NOT NULL DEFAULT '[]',
        ${DbConstants.colItemSavedAt} INTEGER NOT NULL,
        ${DbConstants.colItemUpdatedAt} INTEGER,
        ${DbConstants.colItemLatitude} REAL,
        ${DbConstants.colItemLongitude} REAL,
        ${DbConstants.colItemExpiryDate} INTEGER,
        ${DbConstants.colItemIsArchived} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colItemNotes} TEXT,
        ${DbConstants.colItemCloudId} TEXT,
        ${DbConstants.colItemLastSyncedAt} INTEGER
      )
    ''');

    // ── locations ───────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE ${DbConstants.tableLocations} (
        ${DbConstants.colLocId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colLocUuid} TEXT NOT NULL UNIQUE,
        ${DbConstants.colLocName} TEXT NOT NULL,
        ${DbConstants.colLocFullPath} TEXT,
        ${DbConstants.colLocParentUuid} TEXT,
        ${DbConstants.colLocIconName} TEXT NOT NULL DEFAULT 'folder',
        ${DbConstants.colLocUsageCount} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colLocCreatedAt} INTEGER NOT NULL,
        FOREIGN KEY (${DbConstants.colLocParentUuid})
          REFERENCES ${DbConstants.tableLocations}(${DbConstants.colLocUuid})
          ON DELETE CASCADE
      )
    ''');

    // ── item_location_history ───────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE ${DbConstants.tableHistory} (
        ${DbConstants.colHistId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colHistUuid} TEXT NOT NULL UNIQUE,
        ${DbConstants.colHistItemUuid} TEXT NOT NULL,
        ${DbConstants.colHistLocationUuid} TEXT,
        ${DbConstants.colHistLocationName} TEXT NOT NULL,
        ${DbConstants.colHistMovedAt} INTEGER NOT NULL,
        ${DbConstants.colHistNote} TEXT,
        FOREIGN KEY (${DbConstants.colHistItemUuid})
          REFERENCES ${DbConstants.tableItems}(${DbConstants.colItemUuid})
          ON DELETE CASCADE
      )
    ''');

    // ── pending_sync_operations ─────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE ${DbConstants.tablePendingSync} (
        ${DbConstants.colSyncId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colSyncOperationType} TEXT NOT NULL,
        ${DbConstants.colSyncEntityType} TEXT NOT NULL,
        ${DbConstants.colSyncEntityUuid} TEXT NOT NULL,
        ${DbConstants.colSyncPayload} TEXT NOT NULL,
        ${DbConstants.colSyncFailedAt} INTEGER NOT NULL
      )
    ''');

    // Indexes for common queries
    batch.execute(
        'CREATE INDEX idx_items_location ON ${DbConstants.tableItems}(${DbConstants.colItemLocationUuid})');
    batch.execute(
        'CREATE INDEX idx_items_archived ON ${DbConstants.tableItems}(${DbConstants.colItemIsArchived})');
    batch.execute(
        'CREATE INDEX idx_items_saved_at ON ${DbConstants.tableItems}(${DbConstants.colItemSavedAt} DESC)');
    batch.execute(
        'CREATE INDEX idx_history_item ON ${DbConstants.tableHistory}(${DbConstants.colHistItemUuid})');

    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here as version increments.
    // Example: if (oldVersion < 2) { ... }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
