import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';

import '../domain/models/app_update_action_result.dart';
import '../domain/models/play_update_state.dart';

class PlayInAppUpdateService {
  Future<PlayUpdateState> checkForUpdate() async {
    // Google Play in-app updates are available only for Android builds that
    // were installed through Google Play (production or testing tracks).
    if (kIsWeb || !Platform.isAndroid) {
      return const PlayUpdateState(
        availability: PlayUpdateAvailabilityState.updateNotAvailable,
        installState: PlayUpdateInstallState.unknown,
        flexibleUpdateAllowed: false,
        immediateUpdateAllowed: false,
        availableVersionCode: null,
        clientVersionStalenessDays: null,
        updatePriority: null,
        playPackageName: '',
      );
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      return PlayUpdateState(
        availability: _mapAvailability(info.updateAvailability),
        installState: _mapInstallState(info.installStatus),
        flexibleUpdateAllowed: info.flexibleUpdateAllowed,
        immediateUpdateAllowed: info.immediateUpdateAllowed,
        availableVersionCode: info.availableVersionCode,
        clientVersionStalenessDays: info.clientVersionStalenessDays,
        updatePriority: info.updatePriority,
        playPackageName: info.packageName,
      );
    } on PlatformException catch (error) {
      final kind = _classifyPlatformException(error);
      return PlayUpdateState(
        availability: PlayUpdateAvailabilityState.unknown,
        installState: PlayUpdateInstallState.unknown,
        flexibleUpdateAllowed: false,
        immediateUpdateAllowed: false,
        availableVersionCode: null,
        clientVersionStalenessDays: null,
        updatePriority: null,
        playPackageName: '',
        errorMessage:
            'Play update check failed (${error.code}): ${error.message ?? 'unknown error'}',
        errorKind: kind,
      );
    } catch (error) {
      return PlayUpdateState(
        availability: PlayUpdateAvailabilityState.unknown,
        installState: PlayUpdateInstallState.unknown,
        flexibleUpdateAllowed: false,
        immediateUpdateAllowed: false,
        availableVersionCode: null,
        clientVersionStalenessDays: null,
        updatePriority: null,
        playPackageName: '',
        errorMessage: 'Play update check failed: $error',
        errorKind: PlayUpdateErrorKind.transient,
      );
    }
  }

  // Classify Play Core install-exception codes to separate "we cannot ever
  // check via Play on this device" from "try again later".
  //
  // Codes come through as either PlatformException.code (e.g. "TASK_FAILURE")
  // with a message containing "Install Error(-X)", or directly as "-X".
  // Reference: Play Core InstallErrorCode constants.
  PlayUpdateErrorKind _classifyPlatformException(PlatformException error) {
    final haystack = '${error.code} ${error.message ?? ''}'.toLowerCase();

    // -10 ERROR_APP_NOT_OWNED — app not installed from Play.
    // -6  ERROR_API_NOT_AVAILABLE — in-app updates not supported by Play.
    final bool looksLikeAppNotOwned =
        haystack.contains('install error(-10)') ||
            haystack.contains('error_app_not_owned') ||
            haystack.contains('app_not_owned');
    final bool looksLikeApiUnavailable =
        haystack.contains('install error(-6)') ||
            haystack.contains('error_api_not_available') ||
            haystack.contains('api_not_available');
    if (looksLikeAppNotOwned || looksLikeApiUnavailable) {
      return PlayUpdateErrorKind.playStoreUnavailable;
    }

    // -9 ERROR_PLAY_STORE_NOT_FOUND, -2 ERROR_UNKNOWN via missing services.
    final bool looksLikePlayMissing =
        haystack.contains('install error(-9)') ||
            haystack.contains('play_store_not_found') ||
            haystack.contains('playservicesrepairable') ||
            haystack.contains('google play services');
    if (looksLikePlayMissing) {
      return PlayUpdateErrorKind.playServicesUnavailable;
    }

    return PlayUpdateErrorKind.transient;
  }

  Stream<PlayUpdateInstallState> installStateStream() {
    if (kIsWeb || !Platform.isAndroid) {
      return const Stream<PlayUpdateInstallState>.empty();
    }
    return InAppUpdate.installUpdateListener.map(_mapInstallState);
  }

  Future<AppUpdateActionResult> startFlexibleUpdate() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const AppUpdateActionResult(
        status: AppUpdateActionResultStatus.notAllowed,
        message: 'Flexible updates are only supported on Android.',
      );
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (!info.flexibleUpdateAllowed) {
        return const AppUpdateActionResult(
          status: AppUpdateActionResultStatus.notAllowed,
          message: 'Flexible update is not allowed by Google Play.',
        );
      }

      final result = await InAppUpdate.startFlexibleUpdate();
      return _mapActionResult(result);
    } on PlatformException catch (error) {
      return AppUpdateActionResult(
        status: AppUpdateActionResultStatus.failed,
        message:
            'Flexible update failed (${error.code}): ${error.message ?? 'unknown error'}',
      );
    } catch (error) {
      return AppUpdateActionResult(
        status: AppUpdateActionResultStatus.failed,
        message: 'Flexible update failed: $error',
      );
    }
  }

  Future<AppUpdateActionResult> startImmediateUpdate() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const AppUpdateActionResult(
        status: AppUpdateActionResultStatus.notAllowed,
        message: 'Immediate updates are only supported on Android.',
      );
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (!info.immediateUpdateAllowed) {
        return const AppUpdateActionResult(
          status: AppUpdateActionResultStatus.notAllowed,
          message: 'Immediate update is not allowed by Google Play.',
        );
      }

      final result = await InAppUpdate.performImmediateUpdate();
      return _mapActionResult(result);
    } on PlatformException catch (error) {
      return AppUpdateActionResult(
        status: AppUpdateActionResultStatus.failed,
        message:
            'Immediate update failed (${error.code}): ${error.message ?? 'unknown error'}',
      );
    } catch (error) {
      return AppUpdateActionResult(
        status: AppUpdateActionResultStatus.failed,
        message: 'Immediate update failed: $error',
      );
    }
  }

  Future<AppUpdateActionResult> completeFlexibleUpdate() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const AppUpdateActionResult(
        status: AppUpdateActionResultStatus.notAllowed,
        message: 'Complete flexible update is only supported on Android.',
      );
    }

    try {
      await InAppUpdate.completeFlexibleUpdate();
      return const AppUpdateActionResult.success();
    } on PlatformException catch (error) {
      return AppUpdateActionResult(
        status: AppUpdateActionResultStatus.failed,
        message:
            'Completing flexible update failed (${error.code}): ${error.message ?? 'unknown error'}',
      );
    } catch (error) {
      return AppUpdateActionResult(
        status: AppUpdateActionResultStatus.failed,
        message: 'Completing flexible update failed: $error',
      );
    }
  }

  PlayUpdateAvailabilityState _mapAvailability(
      UpdateAvailability availability) {
    return switch (availability) {
      UpdateAvailability.updateNotAvailable =>
        PlayUpdateAvailabilityState.updateNotAvailable,
      UpdateAvailability.updateAvailable =>
        PlayUpdateAvailabilityState.updateAvailable,
      UpdateAvailability.developerTriggeredUpdateInProgress =>
        PlayUpdateAvailabilityState.developerTriggeredUpdateInProgress,
      UpdateAvailability.unknown => PlayUpdateAvailabilityState.unknown,
    };
  }

  PlayUpdateInstallState _mapInstallState(InstallStatus installStatus) {
    return switch (installStatus) {
      InstallStatus.pending => PlayUpdateInstallState.pending,
      InstallStatus.downloading => PlayUpdateInstallState.downloading,
      InstallStatus.installing => PlayUpdateInstallState.installing,
      InstallStatus.installed => PlayUpdateInstallState.installed,
      InstallStatus.failed => PlayUpdateInstallState.failed,
      InstallStatus.canceled => PlayUpdateInstallState.canceled,
      InstallStatus.downloaded => PlayUpdateInstallState.downloaded,
      InstallStatus.unknown => PlayUpdateInstallState.unknown,
    };
  }

  AppUpdateActionResult _mapActionResult(AppUpdateResult result) {
    return switch (result) {
      AppUpdateResult.success => const AppUpdateActionResult.success(),
      AppUpdateResult.userDeniedUpdate => const AppUpdateActionResult(
          status: AppUpdateActionResultStatus.userDenied,
          message: 'User denied the update flow.',
        ),
      AppUpdateResult.inAppUpdateFailed => const AppUpdateActionResult(
          status: AppUpdateActionResultStatus.failed,
          message: 'Google Play failed to start the update flow.',
        ),
    };
  }
}
