import '../../core/constants/update_constants.dart';

enum EffectiveAppUpdateStatus {
  noUpdate,
  optionalUpdateAvailable,
  forceUpdateRequired,
  downloadingUpdate,
  downloadedPendingInstall,
  updateError,
}

class EffectiveAppUpdateDecision {
  const EffectiveAppUpdateDecision({
    required this.status,
    required this.title,
    required this.message,
    required this.playStoreUrl,
    required this.showChangelog,
    required this.changelogText,
    required this.canStartFlexibleUpdate,
    required this.canStartImmediateUpdate,
    required this.availableVersionCode,
    required this.availableVersionName,
    required this.errorMessage,
  });

  const EffectiveAppUpdateDecision.noUpdate()
      : status = EffectiveAppUpdateStatus.noUpdate,
        title = '',
        message = '',
        playStoreUrl = UpdateConstants.defaultPlayStoreUrl,
        showChangelog = false,
        changelogText = '',
        canStartFlexibleUpdate = false,
        canStartImmediateUpdate = false,
        availableVersionCode = null,
        availableVersionName = '',
        errorMessage = null;

  final EffectiveAppUpdateStatus status;
  final String title;
  final String message;
  final String playStoreUrl;
  final bool showChangelog;
  final String changelogText;
  final bool canStartFlexibleUpdate;
  final bool canStartImmediateUpdate;
  final int? availableVersionCode;
  final String availableVersionName;
  final String? errorMessage;

  bool get isNoUpdate => status == EffectiveAppUpdateStatus.noUpdate;
  bool get isOptionalUpdate =>
      status == EffectiveAppUpdateStatus.optionalUpdateAvailable;
  bool get isForceUpdate =>
      status == EffectiveAppUpdateStatus.forceUpdateRequired;
  bool get isDownloading =>
      status == EffectiveAppUpdateStatus.downloadingUpdate;
  bool get isDownloadedPendingInstall =>
      status == EffectiveAppUpdateStatus.downloadedPendingInstall;
  bool get isError => status == EffectiveAppUpdateStatus.updateError;

  EffectiveAppUpdateDecision copyWith({
    EffectiveAppUpdateStatus? status,
    String? title,
    String? message,
    String? playStoreUrl,
    bool? showChangelog,
    String? changelogText,
    bool? canStartFlexibleUpdate,
    bool? canStartImmediateUpdate,
    int? availableVersionCode,
    bool clearAvailableVersionCode = false,
    String? availableVersionName,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return EffectiveAppUpdateDecision(
      status: status ?? this.status,
      title: title ?? this.title,
      message: message ?? this.message,
      playStoreUrl: playStoreUrl ?? this.playStoreUrl,
      showChangelog: showChangelog ?? this.showChangelog,
      changelogText: changelogText ?? this.changelogText,
      canStartFlexibleUpdate:
          canStartFlexibleUpdate ?? this.canStartFlexibleUpdate,
      canStartImmediateUpdate:
          canStartImmediateUpdate ?? this.canStartImmediateUpdate,
      availableVersionCode: clearAvailableVersionCode
          ? null
          : (availableVersionCode ?? this.availableVersionCode),
      availableVersionName: availableVersionName ?? this.availableVersionName,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
