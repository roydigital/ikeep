import '../../core/constants/update_constants.dart';

enum RemoteUpdateMode {
  none,
  optional,
  force,
}

extension RemoteUpdateModeX on RemoteUpdateMode {
  String get value => switch (this) {
        RemoteUpdateMode.none => 'none',
        RemoteUpdateMode.optional => 'optional',
        RemoteUpdateMode.force => 'force',
      };

  static RemoteUpdateMode fromRaw(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    return switch (normalized) {
      'optional' => RemoteUpdateMode.optional,
      'force' => RemoteUpdateMode.force,
      _ => RemoteUpdateMode.none,
    };
  }
}

class RemoteUpdatePolicy {
  const RemoteUpdatePolicy({
    required this.latestVersionCodeAndroid,
    required this.latestVersionNameAndroid,
    required this.minimumSupportedVersionCodeAndroid,
    required this.updateMode,
    required this.updateTitle,
    required this.updateMessage,
    required this.showChangelog,
    required this.changelogText,
    required this.playStoreUrl,
    required this.isUpdateLive,
    required this.scheduleOptionalReminderAfterDismiss,
    required this.optionalReminderDelayMinutes,
  });

  const RemoteUpdatePolicy.defaults()
      : latestVersionCodeAndroid = 0,
        latestVersionNameAndroid = '',
        minimumSupportedVersionCodeAndroid = 0,
        updateMode = RemoteUpdateMode.none,
        updateTitle = 'Update available',
        updateMessage = 'A new version of Ikeep is available on Google Play.',
        showChangelog = false,
        changelogText = '',
        playStoreUrl = UpdateConstants.defaultPlayStoreUrl,
        isUpdateLive = false,
        scheduleOptionalReminderAfterDismiss = false,
        optionalReminderDelayMinutes = 720;

  final int latestVersionCodeAndroid;
  final String latestVersionNameAndroid;
  final int minimumSupportedVersionCodeAndroid;
  final RemoteUpdateMode updateMode;
  final String updateTitle;
  final String updateMessage;
  final bool showChangelog;
  final String changelogText;
  final String playStoreUrl;
  final bool isUpdateLive;
  final bool scheduleOptionalReminderAfterDismiss;
  final int optionalReminderDelayMinutes;

  bool get hasMinimumVersionFloor => minimumSupportedVersionCodeAndroid > 0;
  bool get hasLatestVersionHint => latestVersionCodeAndroid > 0;

  bool get isForceMode => updateMode == RemoteUpdateMode.force;
  bool get isOptionalMode => updateMode == RemoteUpdateMode.optional;
}
