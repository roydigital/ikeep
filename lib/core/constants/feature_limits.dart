const int cloudBackupLimit = 1000;
const int cloudBackupWarningThreshold = 900;
const int itemPhotoLimit = 3;

// ── PDF upload size policy ──────────────────────────────────────────────────
// Soft limit: PDFs above this size trigger an optimization attempt before
// upload. Files at or below this limit are uploaded directly.
const int pdfSoftLimitBytes = 2 * 1024 * 1024; // 2 MB

// Hard limit: PDFs that remain above this size after optimization (or if
// optimization is unavailable) are rejected outright.
const int pdfHardLimitBytes = 10 * 1024 * 1024; // 10 MB

const String pdfSoftLimitLabel = '2 MB';
const String pdfHardLimitLabel = '10 MB';

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
