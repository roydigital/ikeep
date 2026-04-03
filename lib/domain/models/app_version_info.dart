import '../../core/constants/app_constants.dart';

class AppVersionInfo {
  const AppVersionInfo({
    required this.versionName,
    required this.buildNumber,
    required this.versionCode,
    required this.packageName,
  });

  const AppVersionInfo.unknown()
      : versionName = '',
        buildNumber = '',
        versionCode = 0,
        packageName = '';

  final String versionName;
  final String buildNumber;
  final int versionCode;
  final String packageName;

  bool get hasKnownVersionCode => versionCode > 0;

  String get shortLabel {
    final normalizedVersion = versionName.trim();
    final normalizedBuild = buildNumber.trim();
    if (normalizedVersion.isEmpty && normalizedBuild.isEmpty) {
      return '${AppConstants.appName} Version';
    }
    if (normalizedBuild.isEmpty) {
      return 'v$normalizedVersion';
    }
    if (normalizedVersion.isEmpty) {
      return 'b$normalizedBuild';
    }
    return 'v$normalizedVersion (b$normalizedBuild)';
  }

  String get fullLabel {
    final normalizedVersion = versionName.trim();
    final normalizedBuild = buildNumber.trim();
    if (normalizedVersion.isEmpty && normalizedBuild.isEmpty) {
      return '${AppConstants.appName} Version';
    }
    if (normalizedBuild.isEmpty) {
      return '${AppConstants.appName} Version $normalizedVersion';
    }
    if (normalizedVersion.isEmpty) {
      return '${AppConstants.appName} Version (b$normalizedBuild)';
    }
    return '${AppConstants.appName} Version $normalizedVersion (b$normalizedBuild)';
  }
}
