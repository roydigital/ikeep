import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../core/constants/update_constants.dart';
import '../domain/models/remote_update_policy.dart';

class RemoteUpdatePolicyService {
  Future<RemoteUpdatePolicy> fetchPolicy({
    required String packageName,
    bool forceRefresh = false,
  }) async {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await _initializeIfNeeded(remoteConfig);

    if (forceRefresh) {
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: UpdateConstants.remoteConfigFetchTimeout,
          minimumFetchInterval: Duration.zero,
        ),
      );
    }

    try {
      await remoteConfig.fetchAndActivate();
    } catch (_) {
      // Keep using activated/cache/default values in offline or fetch-failure
      // scenarios. Update UX should still function with last known policy.
    } finally {
      if (forceRefresh) {
        await remoteConfig.setConfigSettings(
          RemoteConfigSettings(
            fetchTimeout: UpdateConstants.remoteConfigFetchTimeout,
            minimumFetchInterval: UpdateConstants.remoteConfigMinFetchInterval,
          ),
        );
      }
    }

    return _parsePolicy(
      remoteConfig,
      packageName: packageName,
    );
  }

  Future<void> _initializeIfNeeded(FirebaseRemoteConfig remoteConfig) async {
    if (_isInitialized) return;

    await remoteConfig.ensureInitialized();
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: UpdateConstants.remoteConfigFetchTimeout,
        minimumFetchInterval: UpdateConstants.remoteConfigMinFetchInterval,
      ),
    );
    await remoteConfig.setDefaults(
      <String, dynamic>{
        UpdateRemoteConfigKeys.latestVersionCodeAndroid: 0,
        UpdateRemoteConfigKeys.latestVersionNameAndroid: '',
        UpdateRemoteConfigKeys.minimumSupportedVersionCodeAndroid: 0,
        UpdateRemoteConfigKeys.updateMode: 'none',
        UpdateRemoteConfigKeys.updateTitle: 'Update available',
        UpdateRemoteConfigKeys.updateMessage:
            'A new version of Ikeep is available on Google Play.',
        UpdateRemoteConfigKeys.showChangelog: false,
        UpdateRemoteConfigKeys.changelogText: '',
        UpdateRemoteConfigKeys.playStoreUrl: '',
        UpdateRemoteConfigKeys.isUpdateLive: false,
        UpdateRemoteConfigKeys.scheduleOptionalReminderAfterDismiss: false,
        UpdateRemoteConfigKeys.optionalReminderDelayMinutes: 720,
      },
    );
    _isInitialized = true;
  }

  RemoteUpdatePolicy _parsePolicy(
    FirebaseRemoteConfig remoteConfig, {
    required String packageName,
  }) {
    final latestCode = _readPositiveInt(
        remoteConfig, UpdateRemoteConfigKeys.latestVersionCodeAndroid);
    final minimumSupportedCode = _readPositiveInt(
      remoteConfig,
      UpdateRemoteConfigKeys.minimumSupportedVersionCodeAndroid,
    );
    final reminderDelayMinutes = _readPositiveInt(
      remoteConfig,
      UpdateRemoteConfigKeys.optionalReminderDelayMinutes,
    );

    final playStoreUrlRaw =
        remoteConfig.getString(UpdateRemoteConfigKeys.playStoreUrl).trim();
    final resolvedPackageName = packageName.trim().isEmpty
        ? UpdateConstants.androidPackageId
        : packageName.trim();
    final fallbackStoreUrl =
        'https://play.google.com/store/apps/details?id=$resolvedPackageName';

    final parsedReminderDelay =
        reminderDelayMinutes <= 0 ? 720 : reminderDelayMinutes;

    return RemoteUpdatePolicy(
      latestVersionCodeAndroid: latestCode,
      latestVersionNameAndroid: remoteConfig
          .getString(UpdateRemoteConfigKeys.latestVersionNameAndroid)
          .trim(),
      minimumSupportedVersionCodeAndroid: minimumSupportedCode,
      updateMode: RemoteUpdateModeX.fromRaw(
        remoteConfig.getString(UpdateRemoteConfigKeys.updateMode),
      ),
      updateTitle:
          remoteConfig.getString(UpdateRemoteConfigKeys.updateTitle).trim(),
      updateMessage:
          remoteConfig.getString(UpdateRemoteConfigKeys.updateMessage).trim(),
      showChangelog: _readBool(
        remoteConfig,
        UpdateRemoteConfigKeys.showChangelog,
      ),
      changelogText:
          remoteConfig.getString(UpdateRemoteConfigKeys.changelogText).trim(),
      playStoreUrl:
          playStoreUrlRaw.isEmpty ? fallbackStoreUrl : playStoreUrlRaw,
      isUpdateLive: _readBool(
        remoteConfig,
        UpdateRemoteConfigKeys.isUpdateLive,
      ),
      scheduleOptionalReminderAfterDismiss: _readBool(
        remoteConfig,
        UpdateRemoteConfigKeys.scheduleOptionalReminderAfterDismiss,
      ),
      optionalReminderDelayMinutes: parsedReminderDelay,
    );
  }

  int _readPositiveInt(FirebaseRemoteConfig config, String key) {
    final directValue = config.getInt(key);
    if (directValue > 0) return directValue;
    final fallback = int.tryParse(config.getString(key).trim()) ?? 0;
    return fallback < 0 ? 0 : fallback;
  }

  bool _readBool(FirebaseRemoteConfig config, String key) {
    final raw = config.getString(key).trim();
    if (raw.isNotEmpty) {
      final normalized = raw.toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return config.getBool(key);
  }

  bool _isInitialized = false;
}
