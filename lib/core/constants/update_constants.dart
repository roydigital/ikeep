/// Constants and keys used by the app update system.
class UpdateConstants {
  UpdateConstants._();

  static const String androidPackageId = 'in.roydigital.ikeep';
  static const String defaultPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=in.roydigital.ikeep';

  /// Keep resume-triggered checks throttled to avoid repeated API calls while
  /// the app bounces between background and foreground.
  static const Duration resumeCheckThrottle = Duration(seconds: 30);

  /// Manual checks can bypass the fetch interval when user taps "Check".
  static const Duration remoteConfigFetchTimeout = Duration(seconds: 12);
  static const Duration remoteConfigMinFetchInterval = Duration(hours: 1);

  /// Optional-update dialog cooldown after a user dismisses it.
  static const Duration optionalPromptCooldown = Duration(hours: 8);
}

/// Firebase Remote Config keys for Android update policy control.
class UpdateRemoteConfigKeys {
  UpdateRemoteConfigKeys._();

  static const String latestVersionCodeAndroid = 'latest_version_code_android';
  static const String latestVersionNameAndroid = 'latest_version_name_android';
  static const String minimumSupportedVersionCodeAndroid =
      'minimum_supported_version_code_android';
  static const String updateMode = 'update_mode';
  static const String updateTitle = 'update_title';
  static const String updateMessage = 'update_message';
  static const String showChangelog = 'show_changelog';
  static const String changelogText = 'changelog_text';
  static const String playStoreUrl = 'play_store_url';
  static const String isUpdateLive = 'is_update_live';

  /// Optional enhancement for reminder-style behavior after dismissing
  /// an optional update prompt.
  static const String scheduleOptionalReminderAfterDismiss =
      'schedule_optional_reminder_after_dismiss';
  static const String optionalReminderDelayMinutes =
      'optional_reminder_delay_minutes';
}

/// SharedPreferences keys for update prompt behavior.
class UpdatePrefsKeys {
  UpdatePrefsKeys._();

  static const String lastOptionalPromptAtMs = 'update_last_optional_prompt_ms';
}
