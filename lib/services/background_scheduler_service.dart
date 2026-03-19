import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../data/database/database_helper.dart';
import '../data/database/item_dao.dart';
import '../providers/settings_provider.dart';
import 'notification_service.dart';

const String weeklyStaleCheckTask = 'ikeep.weekly_stale_check';
const String monthlySeasonalCheckTask = 'ikeep.monthly_seasonal_check';
const String _lastSeasonalMonthKey = 'last_seasonal_check_month';

@pragma('vm:entry-point')
void ikeepWorkmanagerDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final notificationService = NotificationService();
    final itemDao = ItemDao(DatabaseHelper.instance);

    switch (task) {
      case weeklyStaleCheckTask:
        final enabled =
            prefs.getBool(AppSettingsKeys.stillThereReminders) ?? true;
        if (!enabled) return true;

        final staleItem = await itemDao.getRandomStaleItem(
          cutoff: DateTime.now().subtract(const Duration(days: 183)),
        );
        if (staleItem != null) {
          await notificationService.showStillThereReminder(staleItem);
        }
        return true;
      case monthlySeasonalCheckTask:
        final enabled =
            prefs.getBool(AppSettingsKeys.seasonalReminders) ?? true;
        if (!enabled) return true;

        final now = DateTime.now();
        final lastProcessedMonth = prefs.getString(_lastSeasonalMonthKey);
        final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        if (lastProcessedMonth == currentMonth) {
          return true;
        }

        final seasonCategories = NotificationService.seasonCategoriesForMonth(
          now.month,
        );
        if (seasonCategories.isEmpty) {
          await prefs.setString(_lastSeasonalMonthKey, currentMonth);
          return true;
        }

        final seasonalItem =
            await itemDao.getRandomItemBySeasonCategories(seasonCategories);
        if (seasonalItem != null) {
          await notificationService.showSeasonalReminder(
            seasonalItem,
            month: now.month,
          );
        }

        await prefs.setString(_lastSeasonalMonthKey, currentMonth);
        return true;
      default:
        return true;
    }
  });
}

class BackgroundSchedulerService {
  BackgroundSchedulerService._();

  static final BackgroundSchedulerService instance =
      BackgroundSchedulerService._();

  static bool _initialized = false;

  bool get _isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize() async {
    if (!_isSupportedPlatform) return;
    if (_initialized) return;
    await Workmanager().initialize(
      ikeepWorkmanagerDispatcher,
      isInDebugMode: false,
    );
    _initialized = true;
  }

  Future<void> syncNotificationTasks(AppSettings settings) async {
    if (!_isSupportedPlatform) return;
    await initialize();

    if (settings.stillThereRemindersEnabled) {
      await Workmanager().registerPeriodicTask(
        weeklyStaleCheckTask,
        weeklyStaleCheckTask,
        frequency: const Duration(days: 7),
        existingWorkPolicy: ExistingWorkPolicy.update,
        initialDelay: const Duration(days: 7),
        constraints: Constraints(
          networkType: NetworkType.not_required,
        ),
      );
    } else {
      await Workmanager().cancelByUniqueName(weeklyStaleCheckTask);
    }

    if (settings.seasonalRemindersEnabled) {
      await Workmanager().registerPeriodicTask(
        monthlySeasonalCheckTask,
        monthlySeasonalCheckTask,
        // WorkManager cannot guarantee a true calendar-month cadence, so this
        // runs daily and exits unless the current month has not been processed.
        frequency: const Duration(days: 1),
        existingWorkPolicy: ExistingWorkPolicy.update,
        constraints: Constraints(
          networkType: NetworkType.not_required,
        ),
      );
    } else {
      await Workmanager().cancelByUniqueName(monthlySeasonalCheckTask);
    }
  }

  Future<void> syncFromStoredSettings() async {
    if (!_isSupportedPlatform) return;
    final prefs = await SharedPreferences.getInstance();
    await syncNotificationTasks(
      AppSettings(
        stillThereRemindersEnabled:
            prefs.getBool(AppSettingsKeys.stillThereReminders) ?? true,
        seasonalRemindersEnabled:
            prefs.getBool(AppSettingsKeys.seasonalReminders) ?? true,
      ),
    );
  }
}
