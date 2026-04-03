enum AppUpdateActionResultStatus {
  success,
  userDenied,
  failed,
  notAllowed,
}

class AppUpdateActionResult {
  const AppUpdateActionResult({
    required this.status,
    this.message,
  });

  const AppUpdateActionResult.success()
      : status = AppUpdateActionResultStatus.success,
        message = null;

  final AppUpdateActionResultStatus status;
  final String? message;

  bool get isSuccess => status == AppUpdateActionResultStatus.success;
  bool get isUserDenied => status == AppUpdateActionResultStatus.userDenied;
  bool get isNotAllowed => status == AppUpdateActionResultStatus.notAllowed;
}
