// All SQLite table names, column names, and schema version.
class DbConstants {
  DbConstants._();

  static const String dbName = 'ikeep.db';
  static const int dbVersion = 7;

  // ── items ────────────────────────────────────────────────────────────────────
  static const String tableItems = 'items';
  static const String colItemId = 'id';
  static const String colItemUuid = 'uuid';
  static const String colItemName = 'name';
  static const String colItemLocationUuid = 'location_uuid';
  static const String colItemTags = 'tags'; // JSON array string
  static const String colItemImagePaths = 'image_paths'; // JSON array string
  static const String colItemSavedAt = 'saved_at'; // Unix ms
  static const String colItemUpdatedAt = 'updated_at'; // Unix ms
  static const String colItemLatitude = 'latitude';
  static const String colItemLongitude = 'longitude';
  static const String colItemExpiryDate = 'expiry_date'; // Unix ms
  static const String colItemIsArchived = 'is_archived'; // 0 or 1
  static const String colItemNotes = 'notes';
  static const String colItemCloudId = 'cloud_id';
  static const String colItemLastSyncedAt = 'last_synced_at'; // Unix ms
  static const String colItemIsLent = 'is_lent'; // 0 or 1
  static const String colItemLentTo = 'lent_to';
  static const String colItemLentOn = 'lent_on'; // Unix ms
  static const String colItemExpectedReturnDate =
      'expected_return_date'; // Unix ms
  static const String colItemLentReminderAfterDays = 'lent_reminder_after_days';
  static const String colItemIsAvailableForLending =
      'is_available_for_lending'; // 0 or 1
  static const String colItemVisibility = 'visibility'; // private|household|nearby

  // ── locations ────────────────────────────────────────────────────────────────
  static const String tableLocations = 'locations';
  static const String colLocId = 'id';
  static const String colLocUuid = 'uuid';
  static const String colLocName = 'name';
  static const String colLocFullPath = 'full_path';
  static const String colLocParentUuid = 'parent_uuid';
  static const String colLocIconName = 'icon_name';
  static const String colLocUsageCount = 'usage_count';
  static const String colLocCreatedAt = 'created_at'; // Unix ms

  // ── item_location_history ────────────────────────────────────────────────────
  static const String tableHistory = 'item_location_history';
  static const String colHistId = 'id';
  static const String colHistUuid = 'uuid';
  static const String colHistItemUuid = 'item_uuid';
  static const String colHistLocationUuid = 'location_uuid';
  static const String colHistLocationName = 'location_name'; // snapshot
  static const String colHistMovedAt = 'moved_at'; // Unix ms
  static const String colHistNote = 'note';
  static const String colHistMovedByMemberUuid = 'moved_by_member_uuid';
  static const String colHistMovedByName = 'moved_by_name';

  // ── household_members ───────────────────────────────────────────────────────
  static const String tableHouseholdMembers = 'household_members';
  static const String colMemberId = 'id';
  static const String colMemberUuid = 'uuid';
  static const String colMemberName = 'name';
  static const String colMemberInvitedAt = 'invited_at'; // Unix ms
  static const String colMemberIsOwner = 'is_owner'; // 0 or 1

  // ── borrow_requests ─────────────────────────────────────────────────────────
  static const String tableBorrowRequests = 'borrow_requests';
  static const String colBorrowRequestId = 'id';
  static const String colBorrowRequestUuid = 'uuid';
  static const String colBorrowItemUuid = 'item_uuid';
  static const String colBorrowOwnerMemberUuid = 'owner_member_uuid';
  static const String colBorrowOwnerMemberName = 'owner_member_name';
  static const String colBorrowRequesterMemberUuid = 'requester_member_uuid';
  static const String colBorrowRequesterMemberName = 'requester_member_name';
  static const String colBorrowStatus = 'status';
  static const String colBorrowRequestedAt = 'requested_at';
  static const String colBorrowRespondedAt = 'responded_at';
  static const String colBorrowRequestedReturnDate =
      'requested_return_date'; // Unix ms
  static const String colBorrowNote = 'note';

  // ── pending_sync_operations ──────────────────────────────────────────────────
  static const String tablePendingSync = 'pending_sync_operations';
  static const String colSyncId = 'id';
  static const String colSyncOperationType =
      'operation_type'; // upsert | delete
  static const String colSyncEntityType = 'entity_type'; // item | location
  static const String colSyncEntityUuid = 'entity_uuid';
  static const String colSyncPayload = 'payload'; // JSON
  static const String colSyncFailedAt = 'failed_at'; // Unix ms
}
