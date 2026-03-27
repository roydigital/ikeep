import 'cloud_entitlement.dart';

enum CloudGuardrailReasonCode {
  withinExpectedUsage,
  repeatedRestoreBurst,
  repeatedUnchangedMediaDownload,
  heavyDownloadVolume,
  repeatedNoOpSync,
}

enum CloudGuardrailProductionAction {
  none,
  warn,
  throttle,
  block,
}

class CloudGuardrailObservation {
  const CloudGuardrailObservation({
    required this.scope,
    required this.planMode,
    required this.allowedNow,
    required this.reasonCode,
    required this.productionAction,
    required this.message,
    required this.currentObservedUsage,
    required this.futureThreshold,
  });

  final String scope;
  final CloudEntitlementMode planMode;
  final bool allowedNow;
  final CloudGuardrailReasonCode reasonCode;
  final CloudGuardrailProductionAction productionAction;
  final String message;
  final int currentObservedUsage;
  final int futureThreshold;

  bool get wouldWarnInProduction =>
      productionAction == CloudGuardrailProductionAction.warn ||
      productionAction == CloudGuardrailProductionAction.throttle ||
      productionAction == CloudGuardrailProductionAction.block;

  bool get wouldThrottleInProduction =>
      productionAction == CloudGuardrailProductionAction.throttle ||
      productionAction == CloudGuardrailProductionAction.block;

  bool get wouldBlockInProduction =>
      productionAction == CloudGuardrailProductionAction.block;
}
