import 'package:package_info_plus/package_info_plus.dart';

import '../core/constants/app_constants.dart';

class AppInfoService {
  Future<PackageInfo?> _loadPackageInfo() async {
    try {
      return await (_packageInfoFuture ??= PackageInfo.fromPlatform());
    } catch (_) {
      return null;
    }
  }

  Future<String> getStoreVersionLabel() async {
    final packageInfo = await _loadPackageInfo();
    return _formatVersionLabel(
      version: packageInfo?.version,
    );
  }

  Future<String> getBuildLabel() async {
    final packageInfo = await _loadPackageInfo();
    return _formatVersionLabel(
      version: packageInfo?.version,
      buildNumber: packageInfo?.buildNumber,
    );
  }

  String _formatVersionLabel({
    String? version,
    String? buildNumber,
  }) {
    final normalizedVersion = version?.trim() ?? '';
    final normalizedBuildNumber = buildNumber?.trim() ?? '';
    final baseLabel = normalizedVersion.isEmpty
        ? '${AppConstants.appName} Version'
        : '${AppConstants.appName} Version $normalizedVersion';
    if (normalizedBuildNumber.isEmpty) {
      return baseLabel;
    }
    return '$baseLabel (b$normalizedBuildNumber)';
  }

  Future<PackageInfo>? _packageInfoFuture;
}
