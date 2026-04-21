// Future paid-plan caps. During Closed Testing these are observed and logged
// by the quota service, but not hard-enforced at the entitlement layer.
const int cloudBackupLimit = 1000;
const int cloudBackupWarningThreshold = 900;
const int itemPhotoLimit = 3;
const int itemPdfLimit = 1;
const int householdMemberLimit = 5;

// Media byte targets and ceilings used by the cloud contract and upload
// pipeline. Later phases will use the same constants for lazy restore and
// cache invalidation.
const int targetFullImageBytes = 220 * 1024; // ~220 KB
const int minTargetFullImageBytes = 160 * 1024; // ~160 KB
const int maxFullImageBytes = 220 * 1024; // ~220 KB
const int maxFullImageDimensionPx = 1280;
const int fullImageUploadQuality = 80;
const int targetThumbnailBytes = 40 * 1024; // ~40 KB
const int minTargetThumbnailBytes = 20 * 1024; // ~20 KB
const int maxThumbnailBytes = 40 * 1024; // ~40 KB
const int thumbnailMaxDimensionPx = 280;
const int thumbnailUploadQuality = 72;

// ── PDF upload size policy ──────────────────────────────────────────────────
// Soft limit: PDFs above this size trigger an optimization attempt before
// upload. Files at or below this limit are uploaded directly.
const int pdfSoftLimitBytes = 2 * 1024 * 1024; // 2 MB

// Hard limit: PDFs that remain above this size after optimization (or if
// optimization is unavailable) are rejected outright.
const int pdfHardLimitBytes = 10 * 1024 * 1024; // 10 MB
const int maxPdfBytes = pdfHardLimitBytes;

const String pdfSoftLimitLabel = '2 MB';
const String pdfHardLimitLabel = '10 MB';

// ── Text input length caps ──────────────────────────────────────────────────
// Prevent paste-based UI freezes and Firestore 1 MB doc overflow. Enforced at
// the TextField layer via maxLength + LengthLimitingTextInputFormatter.

/// Maximum character length for item name input field
const int itemNameMaxLength = 100;

/// Maximum character length for a single tag
const int tagMaxLength = 30;

/// Maximum character length for the "lent to" person name
const int lentToMaxLength = 60;

/// Maximum character length for location name input
const int locationNameMaxLength = 80;

/// Maximum character length for notes/description (if the app has one — apply only if field exists)
const int itemNotesMaxLength = 500;

/// Maximum character length for email address input (RFC 5321 standard)
const int emailMaxLength = 254;

String pdfHardLimitExceededError() {
  return 'This PDF is too large (max $pdfHardLimitLabel). '
      'Please upload a smaller or cleaner PDF.';
}

String pdfSizeAfterOptimizationError() {
  return 'This PDF is still too large after optimization (max $pdfHardLimitLabel). '
      'Please upload a smaller or cleaner PDF.';
}

const String cloudBackupFairUsageDisclaimer =
    'Cloud backup supports up to 1000 items.';

bool hasReachedCloudBackupLimit({
  required int backedUpCount,
}) {
  return backedUpCount >= cloudBackupLimit;
}

double cloudBackupUsageProgress({
  required int backedUpCount,
}) {
  if (cloudBackupLimit == 0) return 0;
  return (backedUpCount / cloudBackupLimit).clamp(0.0, 1.0);
}

String cloudBackupUsageLabel({
  required int backedUpCount,
}) {
  return '$backedUpCount / $cloudBackupLimit cloud backups used';
}

String cloudBackupQuotaExceededError() {
  return 'Cloud quota exceeded. Cloud backup supports up to '
      '$cloudBackupLimit items. Remove an existing online backup before '
      'adding another item.';
}
