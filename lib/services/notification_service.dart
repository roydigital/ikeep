import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants/notification_constants.dart';
import '../domain/models/item.dart';

/// Wraps [FlutterLocalNotificationsPlugin].
/// Call [initialize] once at app startup before any other method.
class NotificationService {
  NotificationService()
      : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);

    // Create Android notification channels
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          NotificationConstants.expiryChannelId,
          NotificationConstants.expiryChannelName,
          description: NotificationConstants.expiryChannelDesc,
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          NotificationConstants.reminderChannelId,
          NotificationConstants.reminderChannelName,
          description: NotificationConstants.reminderChannelDesc,
          importance: Importance.defaultImportance,
        ),
      );
    }

    _initialized = true;
  }

  /// Schedules an expiry reminder for [item] 3 days before its expiry date.
  /// Silently skips if expiry date is null or already in the past.
  Future<void> scheduleExpiryReminder(Item item) async {
    if (item.expiryDate == null) return;
    final reminderDate = item.expiryDate!.subtract(const Duration(days: 3));
    if (reminderDate.isBefore(DateTime.now())) return;

    final id = _notificationIdForItem(item.uuid);
    await _plugin.zonedSchedule(
      id,
      'Expiry Reminder',
      '${item.name} expires on ${item.expiryDate!.day}/${item.expiryDate!.month}/${item.expiryDate!.year}',
      tz.TZDateTime.from(reminderDate, tz.local),
      NotificationDetails(
        android: const AndroidNotificationDetails(
          NotificationConstants.expiryChannelId,
          NotificationConstants.expiryChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancels a scheduled expiry reminder for [itemUuid].
  Future<void> cancelExpiryReminder(String itemUuid) async {
    await _plugin.cancel(_notificationIdForItem(itemUuid));
  }

  /// Shows a one-time "still there?" reminder notification.
  Future<void> showStillThereReminder(Item item) async {
    await _plugin.show(
      _notificationIdForItem(item.uuid) + NotificationConstants.reminderNotificationIdBase,
      'Still there?',
      'Is your ${item.name} still in ${item.locationName ?? 'the same place'}?',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationConstants.reminderChannelId,
          NotificationConstants.reminderChannelName,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  int _notificationIdForItem(String uuid) {
    return (uuid.hashCode.abs() % 90000) + NotificationConstants.expiryNotificationIdBase;
  }
}
