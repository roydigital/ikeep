import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/constants/db_constants.dart';
import '../../domain/models/location_model.dart';

/// Singleton that opens and owns the SQLite [Database].
/// All DAO classes receive this helper and call [db] to get the raw handle.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const String _defaultRootLocationUuid = 'root-home-local';

  Database? _db;

  static int get _nowMs => DateTime.now().millisecondsSinceEpoch;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // Desktop platforms need the FFI factory.
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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
      onOpen: _onOpen,
      onConfigure: (db) async {
        // Enable FK enforcement
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE ${DbConstants.tableHouseholds} (
        ${DbConstants.colHouseholdId} TEXT PRIMARY KEY,
        ${DbConstants.colHouseholdOwnerId} TEXT NOT NULL,
        ${DbConstants.colHouseholdName} TEXT NOT NULL,
        ${DbConstants.colHouseholdMemberIds} TEXT NOT NULL DEFAULT '[]',
        ${DbConstants.colHouseholdCreatedAt} INTEGER,
        ${DbConstants.colHouseholdUpdatedAt} INTEGER
      )
    ''');

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
        ${DbConstants.colItemWarrantyEndDate} INTEGER,
        ${DbConstants.colItemIsArchived} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colItemNotes} TEXT,
        ${DbConstants.colItemInvoicePath} TEXT,
        ${DbConstants.colItemInvoiceFileName} TEXT,
        ${DbConstants.colItemInvoiceFileSizeBytes} INTEGER,
        ${DbConstants.colItemCloudId} TEXT,
        ${DbConstants.colItemLastSyncedAt} INTEGER,
        ${DbConstants.colItemIsBackedUp} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colItemIsLent} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colItemLentTo} TEXT,
        ${DbConstants.colItemLentOn} INTEGER,
        ${DbConstants.colItemExpectedReturnDate} INTEGER,
        ${DbConstants.colItemSeasonCategory} TEXT NOT NULL DEFAULT 'all_year',
        ${DbConstants.colItemLentReminderAfterDays} INTEGER,
        ${DbConstants.colItemIsAvailableForLending} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colItemVisibility} TEXT NOT NULL DEFAULT 'private',
        ${DbConstants.colItemHouseholdId} TEXT,
        ${DbConstants.colItemSharedWithMemberUuids} TEXT NOT NULL DEFAULT '[]',
        -- Hierarchical location FKs (v13 / Phase 1 refactor)
        ${DbConstants.colItemAreaUuid} TEXT,
        ${DbConstants.colItemRoomUuid} TEXT,
        ${DbConstants.colItemZoneUuid} TEXT
      )
    ''');

    // ── locations ───────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE ${DbConstants.tableLocations} (
        ${DbConstants.colLocId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colLocUuid} TEXT NOT NULL UNIQUE,
        ${DbConstants.colLocName} TEXT NOT NULL,
        ${DbConstants.colLocType} TEXT NOT NULL DEFAULT 'area',
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
        ${DbConstants.colHistMovedByMemberUuid} TEXT,
        ${DbConstants.colHistMovedByName} TEXT,
        ${DbConstants.colHistNote} TEXT,
        ${DbConstants.colHistHouseholdId} TEXT,
        ${DbConstants.colHistUserEmail} TEXT,
        ${DbConstants.colHistActionDescription} TEXT NOT NULL,
        FOREIGN KEY (${DbConstants.colHistItemUuid})
          REFERENCES ${DbConstants.tableItems}(${DbConstants.colItemUuid})
          ON DELETE CASCADE
      )
    ''');

    // ── borrow_requests ─────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE ${DbConstants.tableBorrowRequests} (
        ${DbConstants.colBorrowRequestId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colBorrowRequestUuid} TEXT NOT NULL UNIQUE,
        ${DbConstants.colBorrowItemUuid} TEXT NOT NULL,
        ${DbConstants.colBorrowOwnerMemberUuid} TEXT NOT NULL,
        ${DbConstants.colBorrowOwnerMemberName} TEXT NOT NULL,
        ${DbConstants.colBorrowRequesterMemberUuid} TEXT NOT NULL,
        ${DbConstants.colBorrowRequesterMemberName} TEXT NOT NULL,
        ${DbConstants.colBorrowStatus} TEXT NOT NULL,
        ${DbConstants.colBorrowRequestedAt} INTEGER NOT NULL,
        ${DbConstants.colBorrowRespondedAt} INTEGER,
        ${DbConstants.colBorrowRequestedReturnDate} INTEGER,
        ${DbConstants.colBorrowNote} TEXT,
        FOREIGN KEY (${DbConstants.colBorrowItemUuid})
          REFERENCES ${DbConstants.tableItems}(${DbConstants.colItemUuid})
          ON DELETE CASCADE
      )
    ''');

    _createHouseholdMembersTable(batch);
    _seedOwnerMember(batch);
    _seedDefaultRootLocation(batch);

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
        'CREATE INDEX idx_items_backed_up ON ${DbConstants.tableItems}(${DbConstants.colItemIsBackedUp})');
    batch.execute(
        'CREATE INDEX idx_items_season_category ON ${DbConstants.tableItems}(${DbConstants.colItemSeasonCategory})');
    batch.execute(
        'CREATE INDEX idx_items_warranty_end_date ON ${DbConstants.tableItems}(${DbConstants.colItemWarrantyEndDate})');
    batch.execute(
        'CREATE INDEX idx_items_visibility_household ON ${DbConstants.tableItems}(${DbConstants.colItemVisibility}, ${DbConstants.colItemHouseholdId})');
    batch.execute(
        'CREATE INDEX idx_items_saved_at ON ${DbConstants.tableItems}(${DbConstants.colItemSavedAt} DESC)');
    batch.execute(
        'CREATE INDEX idx_items_area_uuid ON ${DbConstants.tableItems}(${DbConstants.colItemAreaUuid})');
    batch.execute(
        'CREATE INDEX idx_items_room_uuid ON ${DbConstants.tableItems}(${DbConstants.colItemRoomUuid})');
    batch.execute(
        'CREATE INDEX idx_items_zone_uuid ON ${DbConstants.tableItems}(${DbConstants.colItemZoneUuid})');
    batch.execute(
        'CREATE INDEX idx_history_item ON ${DbConstants.tableHistory}(${DbConstants.colHistItemUuid})');
    batch.execute(
        'CREATE INDEX idx_history_household_item ON ${DbConstants.tableHistory}(${DbConstants.colHistHouseholdId}, ${DbConstants.colHistItemUuid})');
    batch.execute(
        'CREATE INDEX idx_borrow_item ON ${DbConstants.tableBorrowRequests}(${DbConstants.colBorrowItemUuid})');
    batch.execute(
        'CREATE INDEX idx_borrow_owner_status ON ${DbConstants.tableBorrowRequests}(${DbConstants.colBorrowOwnerMemberUuid}, ${DbConstants.colBorrowStatus})');
    batch.execute(
        'CREATE INDEX idx_borrow_requester_status ON ${DbConstants.tableBorrowRequests}(${DbConstants.colBorrowRequesterMemberUuid}, ${DbConstants.colBorrowStatus})');

    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here as version increments.
    if (oldVersion < 2) {
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemIsLent,
        'INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemLentTo,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemLentOn,
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemExpectedReturnDate,
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemLentReminderAfterDays,
        'INTEGER',
      );
    }

    if (oldVersion < 3) {
      await _addColumnIfMissing(
        db,
        DbConstants.tableHistory,
        DbConstants.colHistMovedByMemberUuid,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableHistory,
        DbConstants.colHistMovedByName,
        'TEXT',
      );
      await db.execute('''
        UPDATE ${DbConstants.tableHistory}
        SET ${DbConstants.colHistMovedByName} = 'You'
        WHERE ${DbConstants.colHistMovedByName} IS NULL
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DbConstants.tableHouseholdMembers} (
          ${DbConstants.colMemberId} INTEGER PRIMARY KEY AUTOINCREMENT,
          ${DbConstants.colMemberUuid} TEXT NOT NULL UNIQUE,
          ${DbConstants.colMemberName} TEXT NOT NULL,
          ${DbConstants.colMemberInvitedAt} INTEGER NOT NULL,
          ${DbConstants.colMemberIsOwner} INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.insert(
        DbConstants.tableHouseholdMembers,
        {
          DbConstants.colMemberUuid: 'owner-local',
          DbConstants.colMemberName: 'You',
          DbConstants.colMemberInvitedAt: _nowMs,
          DbConstants.colMemberIsOwner: 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DbConstants.tableHouseholdMembers} (
          ${DbConstants.colMemberId} INTEGER PRIMARY KEY AUTOINCREMENT,
          ${DbConstants.colMemberUuid} TEXT NOT NULL UNIQUE,
          ${DbConstants.colMemberName} TEXT NOT NULL,
          ${DbConstants.colMemberInvitedAt} INTEGER NOT NULL,
          ${DbConstants.colMemberIsOwner} INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.insert(
        DbConstants.tableHouseholdMembers,
        {
          DbConstants.colMemberUuid: 'owner-local',
          DbConstants.colMemberName: 'You',
          DbConstants.colMemberInvitedAt: _nowMs,
          DbConstants.colMemberIsOwner: 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    if (oldVersion < 5) {
      await db.insert(
        DbConstants.tableLocations,
        {
          DbConstants.colLocUuid: _defaultRootLocationUuid,
          DbConstants.colLocName: 'Home',
          DbConstants.colLocFullPath: 'Home',
          DbConstants.colLocParentUuid: null,
          DbConstants.colLocIconName: 'folder',
          DbConstants.colLocUsageCount: 0,
          DbConstants.colLocCreatedAt: _nowMs,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    if (oldVersion < 6) {
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemIsAvailableForLending,
        'INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DbConstants.tableBorrowRequests} (
          ${DbConstants.colBorrowRequestId} INTEGER PRIMARY KEY AUTOINCREMENT,
          ${DbConstants.colBorrowRequestUuid} TEXT NOT NULL UNIQUE,
          ${DbConstants.colBorrowItemUuid} TEXT NOT NULL,
          ${DbConstants.colBorrowOwnerMemberUuid} TEXT NOT NULL,
          ${DbConstants.colBorrowOwnerMemberName} TEXT NOT NULL,
          ${DbConstants.colBorrowRequesterMemberUuid} TEXT NOT NULL,
          ${DbConstants.colBorrowRequesterMemberName} TEXT NOT NULL,
          ${DbConstants.colBorrowStatus} TEXT NOT NULL,
          ${DbConstants.colBorrowRequestedAt} INTEGER NOT NULL,
          ${DbConstants.colBorrowRespondedAt} INTEGER,
          ${DbConstants.colBorrowRequestedReturnDate} INTEGER,
          ${DbConstants.colBorrowNote} TEXT,
          FOREIGN KEY (${DbConstants.colBorrowItemUuid})
            REFERENCES ${DbConstants.tableItems}(${DbConstants.colItemUuid})
            ON DELETE CASCADE
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_borrow_item ON ${DbConstants.tableBorrowRequests}(${DbConstants.colBorrowItemUuid})');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_borrow_owner_status ON ${DbConstants.tableBorrowRequests}(${DbConstants.colBorrowOwnerMemberUuid}, ${DbConstants.colBorrowStatus})');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_borrow_requester_status ON ${DbConstants.tableBorrowRequests}(${DbConstants.colBorrowRequesterMemberUuid}, ${DbConstants.colBorrowStatus})');
    }

    if (oldVersion < 7) {
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemVisibility,
        "TEXT NOT NULL DEFAULT 'private'",
      );
      // Migrate: items already shared with household get 'household' visibility
      await db.execute('''
        UPDATE ${DbConstants.tableItems}
        SET ${DbConstants.colItemVisibility} = 'household'
        WHERE ${DbConstants.colItemIsAvailableForLending} = 1
      ''');
    }

    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DbConstants.tableHouseholds} (
          ${DbConstants.colHouseholdId} TEXT PRIMARY KEY,
          ${DbConstants.colHouseholdOwnerId} TEXT NOT NULL,
          ${DbConstants.colHouseholdName} TEXT NOT NULL,
          ${DbConstants.colHouseholdMemberIds} TEXT NOT NULL DEFAULT '[]',
          ${DbConstants.colHouseholdCreatedAt} INTEGER,
          ${DbConstants.colHouseholdUpdatedAt} INTEGER
        )
      ''');
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemHouseholdId,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableHistory,
        DbConstants.colHistHouseholdId,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableHistory,
        DbConstants.colHistUserEmail,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableHistory,
        DbConstants.colHistActionDescription,
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableHouseholdMembers,
        DbConstants.colMemberEmail,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableHouseholdMembers,
        DbConstants.colMemberHouseholdUuid,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableHouseholdMembers,
        DbConstants.colMemberJoinedAt,
        'INTEGER',
      );
      await db.execute('''
        UPDATE ${DbConstants.tableHistory}
        SET ${DbConstants.colHistActionDescription} = COALESCE(
          NULLIF(${DbConstants.colHistNote}, ''),
          'Moved to ' || ${DbConstants.colHistLocationName}
        )
        WHERE ${DbConstants.colHistActionDescription} = ''
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_items_visibility_household ON ${DbConstants.tableItems}(${DbConstants.colItemVisibility}, ${DbConstants.colItemHouseholdId})');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_history_household_item ON ${DbConstants.tableHistory}(${DbConstants.colHistHouseholdId}, ${DbConstants.colHistItemUuid})');
    }

    if (oldVersion < 9) {
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemSharedWithMemberUuids,
        "TEXT NOT NULL DEFAULT '[]'",
      );
    }

    if (oldVersion < 10) {
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemSeasonCategory,
        "TEXT NOT NULL DEFAULT 'all_year'",
      );
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_items_season_category ON ${DbConstants.tableItems}(${DbConstants.colItemSeasonCategory})');
    }

    if (oldVersion < 11) {
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemIsBackedUp,
        'INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_items_backed_up ON ${DbConstants.tableItems}(${DbConstants.colItemIsBackedUp})');
    }

    if (oldVersion < 12) {
      await _addColumnIfMissing(
        db,
        DbConstants.tableLocations,
        DbConstants.colLocType,
        "TEXT NOT NULL DEFAULT 'area'",
      );

      await db.execute('''
        UPDATE ${DbConstants.tableLocations}
        SET ${DbConstants.colLocType} = '${LocationType.area.value}'
        WHERE ${DbConstants.colLocParentUuid} IS NULL
      ''');

      await db.execute('''
        UPDATE ${DbConstants.tableLocations}
        SET ${DbConstants.colLocType} = '${LocationType.room.value}'
        WHERE ${DbConstants.colLocParentUuid} IS NOT NULL
          AND ${DbConstants.colLocUuid} IN (
            SELECT DISTINCT ${DbConstants.colLocParentUuid}
            FROM ${DbConstants.tableLocations}
            WHERE ${DbConstants.colLocParentUuid} IS NOT NULL
          )
      ''');

      await db.execute('''
        UPDATE ${DbConstants.tableLocations}
        SET ${DbConstants.colLocType} = '${LocationType.zone.value}'
        WHERE ${DbConstants.colLocParentUuid} IS NOT NULL
          AND ${DbConstants.colLocUuid} NOT IN (
            SELECT DISTINCT ${DbConstants.colLocParentUuid}
            FROM ${DbConstants.tableLocations}
            WHERE ${DbConstants.colLocParentUuid} IS NOT NULL
          )
      ''');
    }

    // ── v13: Phase 1 — hierarchical location FKs on items ──────────────────
    // Adds area_uuid, room_uuid, zone_uuid as explicit FK columns.
    // These allow per-level filtering without joins. The legacy location_uuid
    // column is kept intact; Phase 5 migration will populate the new columns
    // from the existing locations hierarchy and then null out location_uuid.
    if (oldVersion < 13) {
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemAreaUuid,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemRoomUuid,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemZoneUuid,
        'TEXT',
      );

      // Seed zone_uuid from location_uuid for existing items where the location
      // is a zone — this covers the common case where users have already been
      // assigning items via the location picker (which always picks zones).
      // area_uuid and room_uuid will be backfilled properly in Phase 5 via the
      // LocationHierarchyMigrationService utility.
      await db.execute('''
        UPDATE ${DbConstants.tableItems}
        SET ${DbConstants.colItemZoneUuid} = ${DbConstants.colItemLocationUuid}
        WHERE ${DbConstants.colItemLocationUuid} IS NOT NULL
          AND ${DbConstants.colItemZoneUuid} IS NULL
          AND ${DbConstants.colItemLocationUuid} IN (
            SELECT ${DbConstants.colLocUuid}
            FROM ${DbConstants.tableLocations}
            WHERE ${DbConstants.colLocType} = '${LocationType.zone.value}'
          )
      ''');

      // Indexes for the new columns — allows fast WHERE area_uuid = ?
      // and WHERE room_uuid = ? queries without full-table scans.
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_items_area_uuid '
        'ON ${DbConstants.tableItems}(${DbConstants.colItemAreaUuid})',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_items_room_uuid '
        'ON ${DbConstants.tableItems}(${DbConstants.colItemRoomUuid})',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_items_zone_uuid '
        'ON ${DbConstants.tableItems}(${DbConstants.colItemZoneUuid})',
      );
    }

    if (oldVersion < 14) {
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemWarrantyEndDate,
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemInvoicePath,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemInvoiceFileName,
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        DbConstants.tableItems,
        DbConstants.colItemInvoiceFileSizeBytes,
        'INTEGER',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_items_warranty_end_date '
        'ON ${DbConstants.tableItems}(${DbConstants.colItemWarrantyEndDate})',
      );
    }
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbConstants.tableHouseholds} (
        ${DbConstants.colHouseholdId} TEXT PRIMARY KEY,
        ${DbConstants.colHouseholdOwnerId} TEXT NOT NULL,
        ${DbConstants.colHouseholdName} TEXT NOT NULL,
        ${DbConstants.colHouseholdMemberIds} TEXT NOT NULL DEFAULT '[]',
        ${DbConstants.colHouseholdCreatedAt} INTEGER,
        ${DbConstants.colHouseholdUpdatedAt} INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbConstants.tableHouseholdMembers} (
        ${DbConstants.colMemberId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colMemberUuid} TEXT NOT NULL UNIQUE,
        ${DbConstants.colMemberName} TEXT NOT NULL,
        ${DbConstants.colMemberInvitedAt} INTEGER NOT NULL,
        ${DbConstants.colMemberIsOwner} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colMemberEmail} TEXT,
        ${DbConstants.colMemberHouseholdUuid} TEXT,
        ${DbConstants.colMemberJoinedAt} INTEGER
      )
    ''');
    await db.insert(
      DbConstants.tableHouseholdMembers,
      {
        DbConstants.colMemberUuid: 'owner-local',
        DbConstants.colMemberName: 'You',
        DbConstants.colMemberInvitedAt: _nowMs,
        DbConstants.colMemberIsOwner: 1,
        DbConstants.colMemberJoinedAt: _nowMs,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.insert(
      DbConstants.tableLocations,
      {
        DbConstants.colLocUuid: _defaultRootLocationUuid,
        DbConstants.colLocName: 'Home',
        DbConstants.colLocType: LocationType.area.value,
        DbConstants.colLocFullPath: 'Home',
        DbConstants.colLocParentUuid: null,
        DbConstants.colLocIconName: 'folder',
        DbConstants.colLocUsageCount: 0,
        DbConstants.colLocCreatedAt: _nowMs,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbConstants.tableBorrowRequests} (
        ${DbConstants.colBorrowRequestId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colBorrowRequestUuid} TEXT NOT NULL UNIQUE,
        ${DbConstants.colBorrowItemUuid} TEXT NOT NULL,
        ${DbConstants.colBorrowOwnerMemberUuid} TEXT NOT NULL,
        ${DbConstants.colBorrowOwnerMemberName} TEXT NOT NULL,
        ${DbConstants.colBorrowRequesterMemberUuid} TEXT NOT NULL,
        ${DbConstants.colBorrowRequesterMemberName} TEXT NOT NULL,
        ${DbConstants.colBorrowStatus} TEXT NOT NULL,
        ${DbConstants.colBorrowRequestedAt} INTEGER NOT NULL,
        ${DbConstants.colBorrowRespondedAt} INTEGER,
        ${DbConstants.colBorrowRequestedReturnDate} INTEGER,
        ${DbConstants.colBorrowNote} TEXT,
        FOREIGN KEY (${DbConstants.colBorrowItemUuid})
          REFERENCES ${DbConstants.tableItems}(${DbConstants.colItemUuid})
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String tableName,
    String columnName,
    String columnDefinition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final hasColumn = columns.any((column) => column['name'] == columnName);

    if (hasColumn) return;

    await db.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
    );
  }

  void _createHouseholdMembersTable(Batch batch) {
    batch.execute('''
      CREATE TABLE ${DbConstants.tableHouseholdMembers} (
        ${DbConstants.colMemberId} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DbConstants.colMemberUuid} TEXT NOT NULL UNIQUE,
        ${DbConstants.colMemberName} TEXT NOT NULL,
        ${DbConstants.colMemberInvitedAt} INTEGER NOT NULL,
        ${DbConstants.colMemberIsOwner} INTEGER NOT NULL DEFAULT 0,
        ${DbConstants.colMemberEmail} TEXT,
        ${DbConstants.colMemberHouseholdUuid} TEXT,
        ${DbConstants.colMemberJoinedAt} INTEGER
      )
    ''');
  }

  void _seedOwnerMember(Batch batch) {
    batch.execute('''
      INSERT INTO ${DbConstants.tableHouseholdMembers} (
        ${DbConstants.colMemberUuid},
        ${DbConstants.colMemberName},
        ${DbConstants.colMemberInvitedAt},
        ${DbConstants.colMemberIsOwner},
        ${DbConstants.colMemberJoinedAt}
      ) VALUES ('owner-local', 'You', $_nowMs, 1, $_nowMs)
    ''');
  }

  void _seedDefaultRootLocation(Batch batch) {
    batch.execute('''
      INSERT INTO ${DbConstants.tableLocations} (
        ${DbConstants.colLocUuid},
        ${DbConstants.colLocName},
        ${DbConstants.colLocType},
        ${DbConstants.colLocFullPath},
        ${DbConstants.colLocParentUuid},
        ${DbConstants.colLocIconName},
        ${DbConstants.colLocUsageCount},
        ${DbConstants.colLocCreatedAt}
      ) VALUES (
        '$_defaultRootLocationUuid',
        'Home',
        '${LocationType.area.value}',
        'Home',
        NULL,
        'folder',
        0,
        $_nowMs
      )
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
