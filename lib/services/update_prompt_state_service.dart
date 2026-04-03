import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/update_constants.dart';

class UpdatePromptStateService {
  Future<DateTime?> getLastOptionalPromptAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(UpdatePrefsKeys.lastOptionalPromptAtMs);
    if (raw == null || raw <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> saveOptionalPromptShownAt(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      UpdatePrefsKeys.lastOptionalPromptAtMs,
      timestamp.millisecondsSinceEpoch,
    );
  }
}
