import '../../domain/models/app_update_action_result.dart';
import '../../domain/models/app_version_info.dart';
import '../../domain/models/play_update_state.dart';
import '../../domain/models/remote_update_policy.dart';
import '../../services/app_version_service.dart';
import '../../services/play_in_app_update_service.dart';
import '../../services/remote_update_policy_service.dart';
import 'app_update_repository.dart';

class AppUpdateRepositoryImpl implements AppUpdateRepository {
  AppUpdateRepositoryImpl({
    required AppVersionService appVersionService,
    required PlayInAppUpdateService playInAppUpdateService,
    required RemoteUpdatePolicyService remoteUpdatePolicyService,
  })  : _appVersionService = appVersionService,
        _playInAppUpdateService = playInAppUpdateService,
        _remoteUpdatePolicyService = remoteUpdatePolicyService;

  final AppVersionService _appVersionService;
  final PlayInAppUpdateService _playInAppUpdateService;
  final RemoteUpdatePolicyService _remoteUpdatePolicyService;

  @override
  Future<AppVersionInfo> getInstalledVersion() {
    return _appVersionService.getInstalledVersion();
  }

  @override
  Future<PlayUpdateState> checkPlayUpdate() {
    return _playInAppUpdateService.checkForUpdate();
  }

  @override
  Stream<PlayUpdateInstallState> watchInstallState() {
    return _playInAppUpdateService.installStateStream();
  }

  @override
  Future<RemoteUpdatePolicy> fetchRemotePolicy({
    required String packageName,
    bool forceRefresh = false,
  }) {
    return _remoteUpdatePolicyService.fetchPolicy(
      packageName: packageName,
      forceRefresh: forceRefresh,
    );
  }

  @override
  Future<AppUpdateActionResult> startFlexibleUpdate() {
    return _playInAppUpdateService.startFlexibleUpdate();
  }

  @override
  Future<AppUpdateActionResult> startImmediateUpdate() {
    return _playInAppUpdateService.startImmediateUpdate();
  }

  @override
  Future<AppUpdateActionResult> completeFlexibleUpdate() {
    return _playInAppUpdateService.completeFlexibleUpdate();
  }
}
