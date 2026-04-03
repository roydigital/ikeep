import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class UpdateAnalyticsService {
  UpdateAnalyticsService({
    FirebaseAnalytics? analytics,
  }) : _analytics = analytics ?? FirebaseAnalytics.instance;

  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (error) {
      debugPrint('UpdateAnalytics: failed to log "$name": $error');
    }
  }

  final FirebaseAnalytics _analytics;
}
