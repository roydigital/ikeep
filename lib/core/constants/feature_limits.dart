const int cloudBackupLimit = 1000;
const int cloudBackupWarningThreshold = 900;
const int itemPhotoLimit = 3;

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
