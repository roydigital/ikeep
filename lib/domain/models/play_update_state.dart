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
        errorMessage = null;

  final PlayUpdateAvailabilityState availability;
  final PlayUpdateInstallState installState;
  final bool flexibleUpdateAllowed;
  final bool immediateUpdateAllowed;
  final int? availableVersionCode;
  final int? clientVersionStalenessDays;
  final int? updatePriority;
  final String playPackageName;
  final String? errorMessage;

  bool get isError => (errorMessage?.trim().isNotEmpty ?? false);

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
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
