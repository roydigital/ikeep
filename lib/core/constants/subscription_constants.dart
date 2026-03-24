const int freeCloudBackupLimit = 50;
const int freeCloudBackupWarningThreshold = 45;
const int premiumCloudBackupLimit = 1000;
const int premiumCloudBackupWarningThreshold = 900;
const int freeItemImageLimit = 1;
const int premiumItemImageLimit = 3;

const String googlePlayMonthlySubscriptionId = 'ikeep_plus_monthly';
const String googlePlayYearlySubscriptionId = 'ikeep_plus_yearly';
const String monthlyPlanFallbackPrice = '\$1.99';
const String yearlyPlanFallbackPrice = '\$14.99';
const String googlePlayManageSubscriptionsUrl =
    'https://play.google.com/store/account/subscriptions?package=in.roydigital.ikeep';
const String googlePlaySubscriptionSetupNotice =
    'Replace the placeholder Google Play product IDs with your real Play Console subscription product IDs before release.';
const String googlePlaySubscriptionTestingNotice =
    'Google Play subscriptions only work on Android builds installed from a Play test track using licensed tester accounts.';

const String premiumCloudBackupFeatureLabel = 'Unlimited Cloud Backups';
const String premiumCloudBackupFairUsageDisclaimer =
    'Fair usage applies. Online backup supports up to 1000 items.';

int cloudBackupLimitFor(bool isPremium) {
  return isPremium ? premiumCloudBackupLimit : freeCloudBackupLimit;
}

int cloudBackupWarningThresholdFor(bool isPremium) {
  return isPremium
      ? premiumCloudBackupWarningThreshold
      : freeCloudBackupWarningThreshold;
}

bool hasReachedCloudBackupLimit({
  required bool isPremium,
  required int backedUpCount,
}) {
  return backedUpCount >= cloudBackupLimitFor(isPremium);
}

double cloudBackupUsageProgress({
  required bool isPremium,
  required int backedUpCount,
}) {
  final limit = cloudBackupLimitFor(isPremium);
  if (limit == 0) return 0;
  return (backedUpCount / limit).clamp(0.0, 1.0);
}

String cloudBackupUsageLabel({
  required bool isPremium,
  required int backedUpCount,
}) {
  if (isPremium) {
    return 'Unlimited cloud backups with Ikeep Plus';
  }
  final limit = cloudBackupLimitFor(isPremium);
  return '$backedUpCount / $limit free backups used';
}

String cloudBackupQuotaExceededError({required bool isPremium}) {
  if (isPremium) {
    return 'Cloud quota exceeded. Ikeep Plus includes online backup for up to '
        '$premiumCloudBackupLimit items under our fair usage policy. '
        'Remove an existing online backup before adding another item.';
  }

  return 'Cloud quota exceeded. Free plan includes up to '
      '$freeCloudBackupLimit online backups. Upgrade to Ikeep Plus for up to '
      '$premiumCloudBackupLimit items under our fair usage policy.';
}
