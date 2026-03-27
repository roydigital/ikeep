enum CloudEntitlementMode {
  closedTestingFreeAccess('closed_testing_free_access'),
  paidPlanEnforced('paid_plan_enforced');

  const CloudEntitlementMode(this.storageValue);

  final String storageValue;

  bool get enforcesHardLimits => this == CloudEntitlementMode.paidPlanEnforced;

  static CloudEntitlementMode fromStorageValue(String? value) {
    for (final mode in CloudEntitlementMode.values) {
      if (mode.storageValue == value) {
        return mode;
      }
    }
    return CloudEntitlementMode.closedTestingFreeAccess;
  }
}

enum CloudQuotaReasonCode {
  withinLimits,
  backedUpItemLimit,
  imagesPerItemLimit,
  pdfPerItemLimit,
  householdMemberLimit,
}

class CloudQuotaEvaluation {
  const CloudQuotaEvaluation({
    required this.scope,
    required this.planMode,
    required this.allowedNow,
    required this.wouldBlockInPaidMode,
    required this.reasonCode,
    required this.message,
    required this.currentUsage,
    required this.futureLimit,
  });

  final String scope;
  final CloudEntitlementMode planMode;
  final bool allowedNow;
  final bool wouldBlockInPaidMode;
  final CloudQuotaReasonCode reasonCode;
  final String message;
  final int currentUsage;
  final int futureLimit;
}
