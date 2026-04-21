enum PlayUpdateAvailabilityState {
  unknown,
  updateNotAvailable,
  updateAvailable,
  developerTriggeredUpdateInProgress,
}

enum PlayUpdateInstallState {
  unknown,
  pending,
  downloading,
  installing,
  installed,
  failed,
  canceled,
  downloaded,
}

/// Classifies why a Play update check failed, so callers can choose between
/// a user-friendly fallback (open the Play Store) and a transient retry.
enum PlayUpdateErrorKind {
  none,
  // App wasn't installed from Google Play (side-loaded / debug / other store).
  playStoreUnavailable,
  // Device has no/outdated Play Services or no network.
  playServicesUnavailable,
  // Anything else: genuine transient failure, safe to retry.
  transient,
}

class PlayUpdateState {
  const PlayUpdateState({
    required this.availability,
    required this.installState,
    required this.flexibleUpdateAllowed,
    required this.immediateUpdateAllowed,
    required this.availableVersionCode,
    required this.clientVersionStalenessDays,
    required this.updatePriority,
    required this.playPackageName,
    this.errorMessage,
    this.errorKind = PlayUpdateErrorKind.none,
  });

  const PlayUpdateState.unknown()
      : availability = PlayUpdateAvailabilityState.unknown,
        installState = PlayUpdateInstallState.unknown,
        flexibleUpdateAllowed = false,
        immediateUpdateAllowed = false,
        availableVersionCode = null,
        clientVersionStalenessDays = null,
        updatePriority = null,
        playPackageName = '',
        errorMessage = null,
        errorKind = PlayUpdateErrorKind.none;

  final PlayUpdateAvailabilityState availability;
  final PlayUpdateInstallState installState;
  final bool flexibleUpdateAllowed;
  final bool immediateUpdateAllowed;
  final int? availableVersionCode;
  final int? clientVersionStalenessDays;
  final int? updatePriority;
  final String playPackageName;
  final String? errorMessage;
  final PlayUpdateErrorKind errorKind;

  bool get isError => (errorMessage?.trim().isNotEmpty ?? false);

  bool get isPlayStoreUnavailable =>
      errorKind == PlayUpdateErrorKind.playStoreUnavailable ||
      errorKind == PlayUpdateErrorKind.playServicesUnavailable;

  bool get hasUpdate =>
      availability == PlayUpdateAvailabilityState.updateAvailable ||
      availability ==
          PlayUpdateAvailabilityState.developerTriggeredUpdateInProgress;

  bool get isDownloading =>
      installState == PlayUpdateInstallState.downloading ||
      installState == PlayUpdateInstallState.pending;

  bool get isDownloaded => installState == PlayUpdateInstallState.downloaded;

  bool get isInstallInProgress =>
      installState == PlayUpdateInstallState.installing;

  PlayUpdateState copyWith({
    PlayUpdateAvailabilityState? availability,
    PlayUpdateInstallState? installState,
    bool? flexibleUpdateAllowed,
    bool? immediateUpdateAllowed,
    int? availableVersionCode,
    bool clearAvailableVersionCode = false,
    int? clientVersionStalenessDays,
    bool clearClientVersionStalenessDays = false,
    int? updatePriority,
    bool clearUpdatePriority = false,
    String? playPackageName,
    String? errorMessage,
    bool clearErrorMessage = false,
    PlayUpdateErrorKind? errorKind,
  }) {
    return PlayUpdateState(
      availability: availability ?? this.availability,
      installState: installState ?? this.installState,
      flexibleUpdateAllowed:
          flexibleUpdateAllowed ?? this.flexibleUpdateAllowed,
      immediateUpdateAllowed:
          immediateUpdateAllowed ?? this.immediateUpdateAllowed,
      availableVersionCode: clearAvailableVersionCode
          ? null
          : (availableVersionCode ?? this.availableVersionCode),
      clientVersionStalenessDays: clearClientVersionStalenessDays
          ? null
          : (clientVersionStalenessDays ?? this.clientVersionStalenessDays),
      updatePriority:
          clearUpdatePriority ? null : (updatePriority ?? this.updatePriority),
      playPackageName: playPackageName ?? this.playPackageName,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      errorKind: clearErrorMessage
          ? PlayUpdateErrorKind.none
          : (errorKind ?? this.errorKind),
    );
  }
}
