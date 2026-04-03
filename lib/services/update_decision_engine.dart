import '../domain/models/app_version_info.dart';
import '../domain/models/effective_app_update_decision.dart';
import '../domain/models/play_update_state.dart';
import '../domain/models/remote_update_policy.dart';

class UpdateDecisionEngine {
  const UpdateDecisionEngine();

  EffectiveAppUpdateDecision resolve({
    required AppVersionInfo installedVersion,
    required PlayUpdateState playUpdateState,
    required RemoteUpdatePolicy remotePolicy,
    String? transientErrorMessage,
  }) {
    if (playUpdateState.isDownloaded) {
      return _buildDecision(
        status: EffectiveAppUpdateStatus.downloadedPendingInstall,
        remotePolicy: remotePolicy,
        playUpdateState: playUpdateState,
        fallbackTitle: 'Update ready',
        fallbackMessage:
            'The latest version has finished downloading. Restart to install it.',
      );
    }

    if (playUpdateState.isDownloading || playUpdateState.isInstallInProgress) {
      return _buildDecision(
        status: EffectiveAppUpdateStatus.downloadingUpdate,
        remotePolicy: remotePolicy,
        playUpdateState: playUpdateState,
        fallbackTitle: 'Updating Ikeep',
        fallbackMessage:
            'Your update is in progress. Keep the app open until download finishes.',
      );
    }

    final currentCode = installedVersion.versionCode;
    final latestPolicyCode = remotePolicy.latestVersionCodeAndroid;
    final minPolicyCode = remotePolicy.minimumSupportedVersionCodeAndroid;

    final hasRemoteNewer = currentCode > 0 && latestPolicyCode > currentCode;
    final hasPlayNewer = _hasPlayNewerVersion(
      currentCode: currentCode,
      playUpdateState: playUpdateState,
    );
    final belowMinimum = currentCode > 0 && minPolicyCode > currentCode;
    final forceByRemoteMode =
        remotePolicy.isUpdateLive && remotePolicy.isForceMode;

    if (belowMinimum ||
        (forceByRemoteMode && (hasRemoteNewer || hasPlayNewer))) {
      return _buildDecision(
        status: EffectiveAppUpdateStatus.forceUpdateRequired,
        remotePolicy: remotePolicy,
        playUpdateState: playUpdateState,
        fallbackTitle: 'Update required',
        fallbackMessage:
            'Please update Ikeep to continue. This version is no longer supported.',
      );
    }

    final optionalByRemote = remotePolicy.isUpdateLive &&
        remotePolicy.isOptionalMode &&
        (hasRemoteNewer || hasPlayNewer);
    final optionalByPlayOnly = hasPlayNewer;
    if (optionalByRemote || optionalByPlayOnly) {
      return _buildDecision(
        status: EffectiveAppUpdateStatus.optionalUpdateAvailable,
        remotePolicy: remotePolicy,
        playUpdateState: playUpdateState,
        fallbackTitle: 'Update available',
        fallbackMessage: 'A new version of Ikeep is available on Google Play.',
      );
    }

    if (transientErrorMessage != null &&
        transientErrorMessage.trim().isNotEmpty) {
      return EffectiveAppUpdateDecision(
        status: EffectiveAppUpdateStatus.updateError,
        title: 'Update check failed',
        message: 'Unable to verify updates right now. Please try again later.',
        playStoreUrl: remotePolicy.playStoreUrl,
        showChangelog: false,
        changelogText: '',
        canStartFlexibleUpdate: false,
        canStartImmediateUpdate: false,
        availableVersionCode: playUpdateState.availableVersionCode,
        availableVersionName: remotePolicy.latestVersionNameAndroid,
        errorMessage: transientErrorMessage,
      );
    }

    return const EffectiveAppUpdateDecision.noUpdate();
  }

  bool _hasPlayNewerVersion({
    required int currentCode,
    required PlayUpdateState playUpdateState,
  }) {
    if (!playUpdateState.hasUpdate) return false;
    final playVersionCode = playUpdateState.availableVersionCode;
    if (playVersionCode == null || playVersionCode <= 0) {
      return true;
    }
    if (currentCode <= 0) {
      return true;
    }
    return playVersionCode > currentCode;
  }

  EffectiveAppUpdateDecision _buildDecision({
    required EffectiveAppUpdateStatus status,
    required RemoteUpdatePolicy remotePolicy,
    required PlayUpdateState playUpdateState,
    required String fallbackTitle,
    required String fallbackMessage,
  }) {
    final title = remotePolicy.updateTitle.trim().isNotEmpty
        ? remotePolicy.updateTitle.trim()
        : fallbackTitle;
    final message = remotePolicy.updateMessage.trim().isNotEmpty
        ? remotePolicy.updateMessage.trim()
        : fallbackMessage;
    final changelog = remotePolicy.changelogText.trim();

    return EffectiveAppUpdateDecision(
      status: status,
      title: title,
      message: message,
      playStoreUrl: remotePolicy.playStoreUrl,
      showChangelog: remotePolicy.showChangelog && changelog.isNotEmpty,
      changelogText: changelog,
      canStartFlexibleUpdate: playUpdateState.flexibleUpdateAllowed,
      canStartImmediateUpdate: playUpdateState.immediateUpdateAllowed,
      availableVersionCode: playUpdateState.availableVersionCode,
      availableVersionName: remotePolicy.latestVersionNameAndroid,
      errorMessage: playUpdateState.errorMessage,
    );
  }
}
