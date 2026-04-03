import 'package:package_info_plus/package_info_plus.dart';

import '../domain/models/app_version_info.dart';

class AppVersionService {
  Future<AppVersionInfo> getInstalledVersion() async {
    try {
      final packageInfo =
          await (_packageInfoFuture ??= PackageInfo.fromPlatform());
      final parsedVersionCode =
          int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
      return AppVersionInfo(
        versionName: packageInfo.version.trim(),
        buildNumber: packageInfo.buildNumber.trim(),
        versionCode: parsedVersionCode,
        packageName: packageInfo.packageName.trim(),
      );
    } catch (_) {
      return const AppVersionInfo.unknown();
    }
  }

  Future<PackageInfo>? _packageInfoFuture;
}
