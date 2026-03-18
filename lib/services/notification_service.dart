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
  factory NotificationService() => _instance;

  NotificationService._internal() : _plugin = FlutterLocalNotificationsPlugin();

  static final NotificationService _instance = NotificationService._internal();

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
    await _requestPermissions();

    // Create Android notification channels
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
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
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          NotificationConstants.lentChannelId,
          NotificationConstants.lentChannelName,
          description: NotificationConstants.lentChannelDesc,
          importance: Importance.high,
        ),
      );
    }

    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;

    if (Platform.isIOS || Platform.isMacOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      final macPlugin = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      await macPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  /// Schedules an expiry reminder for [item] 3 days before its expiry date.
  /// Silently skips if expiry date is null or already in the past.
  Future<void> scheduleExpiryReminder(Item item) async {
    await initialize();
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
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancels a scheduled expiry reminder for [itemUuid].
  Future<void> cancelExpiryReminder(String itemUuid) async {
    await initialize();
    await _plugin.cancel(_notificationIdForItem(itemUuid));
  }

  /// Schedules "I Lent It" reminder after [item.lentReminderAfterDays].
  Future<void> scheduleLentReminder(Item item) async {
    await initialize();
    if (!item.isLent ||
        item.lentOn == null ||
        item.lentReminderAfterDays == null) {
      return;
    }

    final reminderDate = item.lentOn!.add(
      Duration(days: item.lentReminderAfterDays!),
    );

    if (reminderDate.isBefore(DateTime.now())) return;

    final id = _lentNotificationIdForItem(item.uuid);
    final who = (item.lentTo?.trim().isNotEmpty ?? false)
        ? item.lentTo!.trim()
        : 'them';

    await _plugin.zonedSchedule(
      id,
      'I Lent It Reminder',
      'Have you got your ${item.name} back from $who?',
      tz.TZDateTime.from(reminderDate, tz.local),
      NotificationDetails(
        android: const AndroidNotificationDetails(
          NotificationConstants.lentChannelId,
          NotificationConstants.lentChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelLentReminder(String itemUuid) async {
    await initialize();
    await _plugin.cancel(_lentNotificationIdForItem(itemUuid));
  }

  /// Shows a one-time "still there?" reminder notification.
  Future<void> showStillThereReminder(Item item) async {
    await initialize();
    await _plugin.show(
      _notificationIdForItem(item.uuid) +
          NotificationConstants.reminderNotificationIdBase,
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

  Future<void> scheduleStillThereDailyReminder() async {
    await initialize();
    await _plugin.periodicallyShow(
      NotificationConstants.stillThereDailyNotificationId,
      'Still there?',
      'Quick check: are your saved items still in their places?',
      RepeatInterval.daily,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationConstants.reminderChannelId,
          NotificationConstants.reminderChannelName,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelStillThereDailyReminder() async {
    await initialize();
    await _plugin.cancel(NotificationConstants.stillThereDailyNotificationId);
  }

  Future<void> rescheduleExpiryReminders(Iterable<Item> items) async {
    await initialize();
    for (final item in items) {
      if (item.expiryDate == null) {
        await cancelExpiryReminder(item.uuid);
        continue;
      }
      await scheduleExpiryReminder(item);
    }
  }

  Future<void> cancelExpiryReminders(Iterable<Item> items) async {
    await initialize();
    for (final item in items) {
      await cancelExpiryReminder(item.uuid);
    }
  }

  Future<void> rescheduleLentReminders(Iterable<Item> items) async {
    await initialize();
    for (final item in items) {
      if (!item.isLent) {
        await cancelLentReminder(item.uuid);
        continue;
      }
      await scheduleLentReminder(item);
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  int _notificationIdForItem(String uuid) {
    return (uuid.hashCode.abs() % 90000) +
        NotificationConstants.expiryNotificationIdBase;
  }

  int _lentNotificationIdForItem(String uuid) {
    return (uuid.hashCode.abs() % 90000) +
        NotificationConstants.lentNotificationIdBase;
  }
}
