// All SQLite table names, column names, and schema version.
class DbConstants {
  DbConstants._();

  static const String dbName = 'ikeep.db';

  /// v20 — adds persistent cloud usage snapshots for quota/accounting.
  static const int dbVersion = 21;

  // households
  static const String tableHouseholds = 'households';
  static const String colHouseholdId = 'household_id';
  static const String colHouseholdOwnerId = 'owner_id';
  static const String colHouseholdName = 'name';
  static const String colHouseholdMemberIds = 'member_ids';
  static const String colHouseholdCreatedAt = 'created_at';
  static const String colHouseholdUpdatedAt = 'updated_at';

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
  static const String colItemLastUpdatedAt = 'last_updated_at'; // Unix ms
  static const String colItemLastMovedAt = 'last_moved_at'; // Unix ms
  static const String colItemLatitude = 'latitude';
  static const String colItemLongitude = 'longitude';
  static const String colItemExpiryDate = 'expiry_date'; // Unix ms
  static const String colItemWarrantyEndDate = 'warranty_end_date'; // Unix ms
  static const String colItemIsArchived = 'is_archived'; // 0 or 1
  static const String colItemNotes = 'notes';
  static const String colItemInvoicePath = 'invoice_path';
  static const String colItemInvoiceFileName = 'invoice_file_name';
  static const String colItemInvoiceFileSizeBytes = 'invoice_file_size_bytes';
  static const String colItemCloudId = 'cloud_id';
  static const String colItemLastSyncedAt = 'last_synced_at'; // Unix ms
  static const String colItemIsBackedUp = 'is_backed_up'; // 0 or 1
  static const String colItemIsLent = 'is_lent'; // 0 or 1
  static const String colItemLentTo = 'lent_to';
  static const String colItemLentOn = 'lent_on'; // Unix ms
  static const String colItemExpectedReturnDate =
      'expected_return_date'; // Unix ms
  static const String colItemSeasonCategory = 'season_category';
  static const String colItemLentReminderAfterDays = 'lent_reminder_after_days';
  static const String colItemIsAvailableForLending =
      'is_available_for_lending'; // 0 or 1
  static const String colItemVisibility = 'visibility'; // private|household
  static const String colItemHouseholdId = 'household_id';
  static const String colItemSharedWithMemberUuids = 'shared_with_member_uuids';

  // Hierarchical location FKs — added in v13 (Phase 1 refactor).
  // All three point to rows in the `locations` table with the matching type.
  static const String colItemAreaUuid = 'area_uuid';
  static const String colItemRoomUuid = 'room_uuid';
  static const String colItemZoneUuid = 'zone_uuid';

  // ── locations ────────────────────────────────────────────────────────────────
  static const String tableLocations = 'locations';
  static const String colLocId = 'id';
  static const String colLocUuid = 'uuid';
  static const String colLocName = 'name';
  static const String colLocType = 'location_type';
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
  static const String colHistHouseholdId = 'household_id';
  static const String colHistUserEmail = 'user_email';
  static const String colHistActionDescription = 'action_description';

  // ── household_members ───────────────────────────────────────────────────────
  static const String tableHouseholdMembers = 'household_members';
  static const String colMemberId = 'id';
  static const String colMemberUuid = 'uuid';
  static const String colMemberName = 'name';
  static const String colMemberInvitedAt = 'invited_at'; // Unix ms
  static const String colMemberIsOwner = 'is_owner'; // 0 or 1
  static const String colMemberEmail = 'email';
  static const String colMemberHouseholdUuid = 'household_uuid';
  static const String colMemberJoinedAt = 'joined_at'; // Unix ms

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

  // media_cache_entries
  static const String tableMediaCache = 'media_cache_entries';
  static const String colMediaCacheKey = 'cache_key';
  static const String colMediaCacheType = 'media_type';
  static const String colMediaStoragePath = 'storage_path';
  static const String colMediaVersion = 'version';
  static const String colMediaContentHash = 'content_hash';
  static const String colMediaLocalFilePath = 'local_file_path';
  static const String colMediaMimeType = 'mime_type';
  static const String colMediaByteSize = 'byte_size';
  static const String colMediaCreatedAt = 'created_at';
  static const String colMediaLastAccessedAt = 'last_accessed_at';

  // item_cloud_media_references
  static const String tableItemCloudMedia = 'item_cloud_media_references';
  static const String colItemCloudMediaItemUuid = 'item_uuid';
  static const String colItemCloudMediaRole = 'media_role';
  static const String colItemCloudMediaSlotIndex = 'slot_index';
  static const String colItemCloudMediaStoragePath = 'storage_path';
  static const String colItemCloudMediaThumbnailPath = 'thumbnail_path';
  static const String colItemCloudMediaMimeType = 'mime_type';
  static const String colItemCloudMediaByteSize = 'byte_size';
  static const String colItemCloudMediaContentHash = 'content_hash';
  static const String colItemCloudMediaVersion = 'version';
  static const String colItemCloudMediaUpdatedAt = 'updated_at';

  // sync_checkpoints
  static const String tableSyncCheckpoints = 'sync_checkpoints';
  static const String colSyncCheckpointScope = 'sync_scope';
  static const String colSyncCheckpointHouseholdId = 'household_id';
  static const String colSyncCheckpointLastPullAt = 'last_successful_pull_at';
  static const String colSyncCheckpointLastPushAt = 'last_successful_push_at';
  static const String colSyncCheckpointLastFullSyncAt = 'last_full_sync_at';
  static const String colSyncCheckpointRemoteCursor =
      'last_known_remote_checkpoint';
  static const String colSyncCheckpointUpdatedAt = 'updated_at';

  // cloud_usage_snapshots
  static const String tableCloudUsageSnapshots = 'cloud_usage_snapshots';
  static const String colCloudUsageScope = 'usage_scope';
  static const String colCloudUsageHouseholdId = 'household_id';
  static const String colCloudUsagePlanMode = 'plan_mode';
  static const String colCloudUsageBackedUpItemCount = 'backed_up_item_count';
  static const String colCloudUsageTotalImageCount = 'total_image_count';
  static const String colCloudUsageTotalPdfCount = 'total_pdf_count';
  static const String colCloudUsageTotalStoredBytes = 'total_stored_bytes';
  static const String colCloudUsageHouseholdMemberCount =
      'household_member_count';
  static const String colCloudUsageUpdatedAt = 'updated_at';

  // cloud_observation_metrics
  static const String tableCloudObservationMetrics =
      'cloud_observation_metrics';
  static const String colCloudObservationScope = 'observation_scope';
  static const String colCloudObservationPlanMode = 'plan_mode';
  static const String colCloudObservationRestoreCount = 'restore_count';
  static const String colCloudObservationRestoreBurstCount =
      'restore_burst_count';
  static const String colCloudObservationFullMediaHydrationCount =
      'full_media_hydration_count';
  static const String colCloudObservationMetadataOnlyRestoreCount =
      'metadata_only_restore_count';
  static const String colCloudObservationThumbnailDownloadCount =
      'thumbnail_download_count';
  static const String colCloudObservationFullImageDownloadCount =
      'full_image_download_count';
  static const String colCloudObservationPdfDownloadCount =
      'pdf_download_count';
  static const String colCloudObservationEstimatedDownloadBytes =
      'estimated_download_bytes';
  static const String colCloudObservationEstimatedUploadBytes =
      'estimated_upload_bytes';
  static const String colCloudObservationRepeatedSyncCount =
      'repeated_sync_count';
  static const String colCloudObservationLastRestoreAt = 'last_restore_at';
  static const String colCloudObservationLastHeavyDownloadAt =
      'last_heavy_download_at';
  static const String colCloudObservationLastSyncAt = 'last_sync_at';
  static const String colCloudObservationUpdatedAt = 'updated_at';

  // cloud_media_observation_activity
  static const String tableCloudMediaObservation =
      'cloud_media_observation_activity';
  static const String colCloudMediaObservationKey = 'activity_key';
  static const String colCloudMediaObservationType = 'media_type';
  static const String colCloudMediaObservationStoragePath = 'storage_path';
  static const String colCloudMediaObservationVersion = 'version';
  static const String colCloudMediaObservationContentHash = 'content_hash';
  static const String colCloudMediaObservationDownloadCount = 'download_count';
  static const String colCloudMediaObservationTotalDownloadedBytes =
      'total_downloaded_bytes';
  static const String colCloudMediaObservationLastDownloadedBytes =
      'last_downloaded_bytes';
  static const String colCloudMediaObservationCreatedAt = 'created_at';
  static const String colCloudMediaObservationLastDownloadedAt =
      'last_downloaded_at';
  static const String colCloudMediaObservationUpdatedAt = 'updated_at';
}
