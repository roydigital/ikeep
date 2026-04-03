import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/update_constants.dart';
import '../data/repositories/app_update_repository.dart';
import '../data/repositories/app_update_repository_impl.dart';
import '../domain/models/app_update_action_result.dart';
import '../domain/models/app_version_info.dart';
import '../domain/models/effective_app_update_decision.dart';
import '../domain/models/play_update_state.dart';
import '../domain/models/remote_update_policy.dart';
import '../services/app_version_service.dart';
import '../services/play_in_app_update_service.dart';
import '../services/remote_update_policy_service.dart';
import '../services/notification_service.dart';
import '../services/update_analytics_service.dart';
import '../services/update_decision_engine.dart';
import '../services/update_prompt_state_service.dart';
import 'service_providers.dart';

enum AppUpdateCheckReason {
  appLaunch,
  appResume,
  manual,
  installStateEvent,
}

extension AppUpdateCheckReasonX on AppUpdateCheckReason {
  String get value => switch (this) {
        AppUpdateCheckReason.appLaunch => 'app_launch',
        AppUpdateCheckReason.appResume => 'app_resume',
        AppUpdateCheckReason.manual => 'manual',
        AppUpdateCheckReason.installStateEvent => 'install_state_event',
      };
}

enum UpdateNowActionKind {
  none,
  startedFlexible,
  startedImmediate,
  completedFlexibleInstall,
  openStoreFallback,
  failed,
  userDenied,
}

class UpdateNowActionResult {
  const UpdateNowActionResult({
    required this.action,
    this.message,
  });

  const UpdateNowActionResult.none()
      : action = UpdateNowActionKind.none,
        message = null;

  final UpdateNowActionKind action;
  final String? message;

  bool get shouldOpenStore => action == UpdateNowActionKind.openStoreFallback;
}

class AppUpdateControllerState {
  const AppUpdateControllerState({
    required this.installedVersion,
    required this.playUpdateState,
    required this.remotePolicy,
    required this.decision,
    required this.isChecking,
    required this.isUpdateActionInProgress,
    required this.optionalPromptDismissedForSession,
    required this.shouldShowOptionalDialog,
    this.lastCheckedAt,
    this.lastCheckReason,
    this.lastErrorMessage,
  });

  const AppUpdateControllerState.initial()
      : installedVersion = const AppVersionInfo.unknown(),
        playUpdateState = const PlayUpdateState.unknown(),
        remotePolicy = const RemoteUpdatePolicy.defaults(),
        decision = const EffectiveAppUpdateDecision.noUpdate(),
        isChecking = false,
        isUpdateActionInProgress = false,
        optionalPromptDismissedForSession = false,
        shouldShowOptionalDialog = false,
        lastCheckedAt = null,
        lastCheckReason = null,
        lastErrorMessage = null;

  final AppVersionInfo installedVersion;
  final PlayUpdateState playUpdateState;
  final RemoteUpdatePolicy remotePolicy;
  final EffectiveAppUpdateDecision decision;
  final bool isChecking;
  final bool isUpdateActionInProgress;
  final bool optionalPromptDismissedForSession;
  final bool shouldShowOptionalDialog;
  final DateTime? lastCheckedAt;
  final AppUpdateCheckReason? lastCheckReason;
  final String? lastErrorMessage;

  AppUpdateControllerState copyWith({
    AppVersionInfo? installedVersion,
    PlayUpdateState? playUpdateState,
    RemoteUpdatePolicy? remotePolicy,
    EffectiveAppUpdateDecision? decision,
    bool? isChecking,
    bool? isUpdateActionInProgress,
    bool? optionalPromptDismissedForSession,
    bool? shouldShowOptionalDialog,
    DateTime? lastCheckedAt,
    bool clearLastCheckedAt = false,
    AppUpdateCheckReason? lastCheckReason,
    bool clearLastCheckReason = false,
    String? lastErrorMessage,
    bool clearLastErrorMessage = false,
  }) {
    return AppUpdateControllerState(
      installedVersion: installedVersion ?? this.installedVersion,
      playUpdateState: playUpdateState ?? this.playUpdateState,
      remotePolicy: remotePolicy ?? this.remotePolicy,
      decision: decision ?? this.decision,
      isChecking: isChecking ?? this.isChecking,
      isUpdateActionInProgress:
          isUpdateActionInProgress ?? this.isUpdateActionInProgress,
      optionalPromptDismissedForSession: optionalPromptDismissedForSession ??
          this.optionalPromptDismissedForSession,
      shouldShowOptionalDialog:
          shouldShowOptionalDialog ?? this.shouldShowOptionalDialog,
      lastCheckedAt:
          clearLastCheckedAt ? null : (lastCheckedAt ?? this.lastCheckedAt),
      lastCheckReason: clearLastCheckReason
          ? null
          : (lastCheckReason ?? this.lastCheckReason),
      lastErrorMessage: clearLastErrorMessage
          ? null
          : (lastErrorMessage ?? this.lastErrorMessage),
    );
  }
}

final appVersionServiceProvider = Provider<AppVersionService>(
  (ref) => AppVersionService(),
);

final playInAppUpdateServiceProvider = Provider<PlayInAppUpdateService>(
  (ref) => PlayInAppUpdateService(),
);

final remoteUpdatePolicyServiceProvider = Provider<RemoteUpdatePolicyService>(
  (ref) => RemoteUpdatePolicyService(),
);

final updateDecisionEngineProvider = Provider<UpdateDecisionEngine>(
  (ref) => const UpdateDecisionEngine(),
);

final updateAnalyticsServiceProvider = Provider<UpdateAnalyticsService>(
  (ref) => UpdateAnalyticsService(),
);

final updatePromptStateServiceProvider = Provider<UpdatePromptStateService>(
  (ref) => UpdatePromptStateService(),
);

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>(
  (ref) => AppUpdateRepositoryImpl(
    appVersionService: ref.watch(appVersionServiceProvider),
    playInAppUpdateService: ref.watch(playInAppUpdateServiceProvider),
    remoteUpdatePolicyService: ref.watch(remoteUpdatePolicyServiceProvider),
  ),
);

final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateControllerState>(
  AppUpdateController.new,
);

final effectiveAppUpdateDecisionProvider = Provider<EffectiveAppUpdateDecision>(
  (ref) => ref.watch(appUpdateControllerProvider).decision,
);

final installedAppVersionInfoProvider = Provider<AppVersionInfo>(
  (ref) => ref.watch(appUpdateControllerProvider).installedVersion,
);

class AppUpdateController extends Notifier<AppUpdateControllerState> {
  @override
  AppUpdateControllerState build() {
    Future<void>.delayed(Duration.zero, _attachInstallStateListener);
    ref.onDispose(() {
      unawaited(_installStateSubscription?.cancel());
    });
    return const AppUpdateControllerState.initial();
  }

  Future<void> initialize() async {
    await checkForUpdates(reason: AppUpdateCheckReason.appLaunch);
  }

  Future<void> checkForUpdates({
    AppUpdateCheckReason reason = AppUpdateCheckReason.appLaunch,
    bool forceRemoteFetch = false,
  }) async {
    if (state.isChecking) return;
    if (!_shouldRunCheck(reason)) return;

    final previousDecision = state.decision;
    final now = DateTime.now();

    state = state.copyWith(
      isChecking: true,
      shouldShowOptionalDialog: false,
      lastCheckReason: reason,
    );

    unawaited(
      _analytics.logEvent(
        'update_check_started',
        parameters: <String, Object>{
          'reason': reason.value,
        },
      ),
    );

    try {
      final installedVersion = await _repository.getInstalledVersion();
      final playUpdateState = await _repository.checkPlayUpdate();
      final remotePolicy = await _repository.fetchRemotePolicy(
        packageName: installedVersion.packageName,
        forceRefresh: forceRemoteFetch || reason == AppUpdateCheckReason.manual,
      );

      final decision = _decisionEngine.resolve(
        installedVersion: installedVersion,
        playUpdateState: playUpdateState,
        remotePolicy: remotePolicy,
        transientErrorMessage: playUpdateState.errorMessage,
      );

      final shouldResetDismissed = decision.isOptionalUpdate &&
          previousDecision.availableVersionCode !=
              decision.availableVersionCode;
      final isOptionalDismissedForSession = shouldResetDismissed
          ? false
          : (decision.isOptionalUpdate
              ? state.optionalPromptDismissedForSession
              : false);

      final shouldShowDialog = await _shouldShowOptionalDialog(
        decision: decision,
        reason: reason,
        optionalDismissedForSession: isOptionalDismissedForSession,
      );

      state = state.copyWith(
        installedVersion: installedVersion,
        playUpdateState: playUpdateState,
        remotePolicy: remotePolicy,
        decision: decision,
        isChecking: false,
        optionalPromptDismissedForSession: isOptionalDismissedForSession,
        shouldShowOptionalDialog: shouldShowDialog,
        lastCheckedAt: now,
        lastErrorMessage: playUpdateState.errorMessage,
      );

      await _emitAvailabilityAnalytics(
        previousDecision: previousDecision,
        currentDecision: decision,
      );

      if (decision.isNoUpdate) {
        await _notificationService.cancelUpdateReminder();
      }
    } catch (error) {
      final errorMessage = 'Update check failed: $error';
      final fallbackDecision = _decisionEngine.resolve(
        installedVersion: state.installedVersion,
        playUpdateState: state.playUpdateState,
        remotePolicy: state.remotePolicy,
        transientErrorMessage: errorMessage,
      );
      state = state.copyWith(
        decision: fallbackDecision,
        isChecking: false,
        lastCheckedAt: now,
        lastErrorMessage: errorMessage,
      );

      await _analytics.logEvent(
        'update_flow_failed',
        parameters: <String, Object>{
          'stage': 'check',
          'reason': reason.value,
          'error': error.runtimeType.toString(),
        },
      );
    }
  }

  Future<void> markOptionalDialogShown() async {
    if (!state.shouldShowOptionalDialog) return;
    state = state.copyWith(shouldShowOptionalDialog: false);
    await _promptState.saveOptionalPromptShownAt(DateTime.now());
  }

  Future<void> dismissOptionalPrompt() async {
    if (!state.decision.isOptionalUpdate) return;
    state = state.copyWith(
      optionalPromptDismissedForSession: true,
      shouldShowOptionalDialog: false,
    );
    await _promptState.saveOptionalPromptShownAt(DateTime.now());
    await _scheduleReminderIfConfigured();
  }

  Future<UpdateNowActionResult> runPrimaryUpdateAction() async {
    if (state.isUpdateActionInProgress) {
      return const UpdateNowActionResult.none();
    }
    final decision = state.decision;
    if (decision.isNoUpdate) {
      return const UpdateNowActionResult.none();
    }
    if (decision.isDownloading) {
      return const UpdateNowActionResult.none();
    }

    state = state.copyWith(
      isUpdateActionInProgress: true,
      shouldShowOptionalDialog: false,
    );

    await _analytics.logEvent(
      'update_cta_clicked',
      parameters: <String, Object>{
        'status': decision.status.name,
      },
    );

    final _ActionPlan plan = _resolveActionPlan(decision);
    if (plan == _ActionPlan.openStoreFallback) {
      state = state.copyWith(isUpdateActionInProgress: false);
      return const UpdateNowActionResult(
        action: UpdateNowActionKind.openStoreFallback,
      );
    }

    final AppUpdateActionResult actionResult;
    if (plan == _ActionPlan.startFlexible) {
      actionResult = await _repository.startFlexibleUpdate();
    } else if (plan == _ActionPlan.startImmediate) {
      actionResult = await _repository.startImmediateUpdate();
    } else if (plan == _ActionPlan.completeFlexibleInstall) {
      actionResult = await _repository.completeFlexibleUpdate();
    } else {
      actionResult = const AppUpdateActionResult(
        status: AppUpdateActionResultStatus.notAllowed,
      );
    }

    if (actionResult.isSuccess) {
      await _handleSuccessfulAction(plan);
      state = state.copyWith(isUpdateActionInProgress: false);
      await checkForUpdates(
        reason: AppUpdateCheckReason.manual,
        forceRemoteFetch: false,
      );
      return UpdateNowActionResult(
        action: switch (plan) {
          _ActionPlan.startFlexible => UpdateNowActionKind.startedFlexible,
          _ActionPlan.startImmediate => UpdateNowActionKind.startedImmediate,
          _ActionPlan.completeFlexibleInstall =>
            UpdateNowActionKind.completedFlexibleInstall,
          _ActionPlan.openStoreFallback =>
            UpdateNowActionKind.openStoreFallback,
        },
      );
    }

    state = state.copyWith(isUpdateActionInProgress: false);

    if (actionResult.isUserDenied) {
      await _analytics.logEvent(
        'update_flow_failed',
        parameters: <String, Object>{
          'stage': 'action',
          'reason': 'user_denied',
        },
      );
      return UpdateNowActionResult(
        action: UpdateNowActionKind.userDenied,
        message: actionResult.message ?? 'Update cancelled.',
      );
    }

    if (actionResult.isNotAllowed) {
      return const UpdateNowActionResult(
        action: UpdateNowActionKind.openStoreFallback,
      );
    }

    await _analytics.logEvent(
      'update_flow_failed',
      parameters: <String, Object>{
        'stage': 'action',
        'reason': actionResult.status.name,
      },
    );
    return UpdateNowActionResult(
      action: UpdateNowActionKind.failed,
      message: actionResult.message ?? 'Unable to start update.',
    );
  }

  Future<void> _handleSuccessfulAction(_ActionPlan plan) async {
    if (plan == _ActionPlan.startFlexible) {
      state = state.copyWith(
        decision: state.decision.copyWith(
          status: EffectiveAppUpdateStatus.downloadingUpdate,
        ),
      );
      return;
    }

    if (plan == _ActionPlan.completeFlexibleInstall) {
      await _analytics.logEvent('flexible_update_completed');
      await _notificationService.cancelUpdateReminder();
    }
  }

  _ActionPlan _resolveActionPlan(EffectiveAppUpdateDecision decision) {
    if (decision.isDownloadedPendingInstall) {
      return _ActionPlan.completeFlexibleInstall;
    }
    if (decision.canStartImmediateUpdate &&
        (decision.isForceUpdate || !decision.canStartFlexibleUpdate)) {
      return _ActionPlan.startImmediate;
    }
    if (decision.canStartFlexibleUpdate) {
      return _ActionPlan.startFlexible;
    }
    if (decision.canStartImmediateUpdate) {
      return _ActionPlan.startImmediate;
    }
    return _ActionPlan.openStoreFallback;
  }

  bool _shouldRunCheck(AppUpdateCheckReason reason) {
    if (reason != AppUpdateCheckReason.appResume) return true;
    final last = state.lastCheckedAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >=
        UpdateConstants.resumeCheckThrottle;
  }

  Future<bool> _shouldShowOptionalDialog({
    required EffectiveAppUpdateDecision decision,
    required AppUpdateCheckReason reason,
    required bool optionalDismissedForSession,
  }) async {
    if (!decision.isOptionalUpdate) return false;
    if (optionalDismissedForSession) return false;
    if (reason == AppUpdateCheckReason.manual ||
        reason == AppUpdateCheckReason.installStateEvent) {
      return false;
    }

    final lastShownAt = await _promptState.getLastOptionalPromptAt();
    if (lastShownAt == null) return true;
    return DateTime.now().difference(lastShownAt) >=
        UpdateConstants.optionalPromptCooldown;
  }

  Future<void> _emitAvailabilityAnalytics({
    required EffectiveAppUpdateDecision previousDecision,
    required EffectiveAppUpdateDecision currentDecision,
  }) async {
    if (currentDecision.isOptionalUpdate &&
        !previousDecision.isOptionalUpdate) {
      await _analytics.logEvent(
        'update_available_optional',
        parameters: <String, Object>{
          if (currentDecision.availableVersionCode != null)
            'available_version_code': currentDecision.availableVersionCode!,
        },
      );
      return;
    }

    if (currentDecision.isForceUpdate && !previousDecision.isForceUpdate) {
      await _analytics.logEvent(
        'update_available_force',
        parameters: <String, Object>{
          if (currentDecision.availableVersionCode != null)
            'available_version_code': currentDecision.availableVersionCode!,
        },
      );
    }
  }

  Future<void> _scheduleReminderIfConfigured() async {
    final decision = state.decision;
    final policy = state.remotePolicy;
    if (!decision.isOptionalUpdate ||
        !policy.scheduleOptionalReminderAfterDismiss) {
      return;
    }

    await _notificationService.scheduleUpdateReminder(
      title:
          decision.title.trim().isEmpty ? 'Update available' : decision.title,
      body: decision.message.trim().isEmpty
          ? 'A new version of Ikeep is available in Google Play.'
          : decision.message,
      after: Duration(minutes: policy.optionalReminderDelayMinutes),
    );
  }

  void _attachInstallStateListener() {
    if (_installStateSubscription != null) return;
    _installStateSubscription = _repository.watchInstallState().listen(
      (PlayUpdateInstallState installState) {
        final previousInstallState = state.playUpdateState.installState;
        final updatedPlayState = state.playUpdateState.copyWith(
          installState: installState,
          clearErrorMessage: true,
        );
        final decision = _decisionEngine.resolve(
          installedVersion: state.installedVersion,
          playUpdateState: updatedPlayState,
          remotePolicy: state.remotePolicy,
          transientErrorMessage: state.lastErrorMessage,
        );

        state = state.copyWith(
          playUpdateState: updatedPlayState,
          decision: decision,
        );

        if (installState == PlayUpdateInstallState.downloaded &&
            previousInstallState != PlayUpdateInstallState.downloaded) {
          unawaited(_analytics.logEvent('flexible_update_downloaded'));
        }
      },
    );
  }

  AppUpdateRepository get _repository => ref.read(appUpdateRepositoryProvider);
  UpdateDecisionEngine get _decisionEngine =>
      ref.read(updateDecisionEngineProvider);
  UpdateAnalyticsService get _analytics =>
      ref.read(updateAnalyticsServiceProvider);
  UpdatePromptStateService get _promptState =>
      ref.read(updatePromptStateServiceProvider);
  NotificationService get _notificationService =>
      ref.read(notificationServiceProvider);

  StreamSubscription<PlayUpdateInstallState>? _installStateSubscription;
}

enum _ActionPlan {
  startFlexible,
  startImmediate,
  completeFlexibleInstall,
  openStoreFallback,
}
