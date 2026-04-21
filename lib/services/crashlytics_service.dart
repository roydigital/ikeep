import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class CrashlyticsService {
  CrashlyticsService._();

  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  static Future<void> logError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    return _crashlytics.recordError(
      error,
      stack,
      reason: reason,
      fatal: fatal,
    );
  }

  static Future<void> setUserId(String uid) {
    return _crashlytics.setUserIdentifier(uid);
  }

  static Future<void> log(String message) {
    return _crashlytics.log(message);
  }
}
