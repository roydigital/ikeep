import '../../domain/models/app_update_action_result.dart';
import '../../domain/models/app_version_info.dart';
import '../../domain/models/play_update_state.dart';
import '../../domain/models/remote_update_policy.dart';

abstract class AppUpdateRepository {
  Future<AppVersionInfo> getInstalledVersion();

  Future<PlayUpdateState> checkPlayUpdate();

  Stream<PlayUpdateInstallState> watchInstallState();

  Future<RemoteUpdatePolicy> fetchRemotePolicy({
    required String packageName,
    bool forceRefresh = false,
  });

  Future<AppUpdateActionResult> startFlexibleUpdate();

  Future<AppUpdateActionResult> startImmediateUpdate();

  Future<AppUpdateActionResult> completeFlexibleUpdate();
}
