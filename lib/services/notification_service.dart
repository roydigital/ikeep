import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants/notification_constants.dart';
import '../domain/models/item.dart';

class NotificationService {
  factory NotificationService() => _instance;

  NotificationService._internal() : _plugin = FlutterLocalNotificationsPlugin();

  static final NotificationService _instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(settings);

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

  static List<String> seasonCategoriesForMonth(int month) {
    switch (month) {
      case DateTime.december:
        return const ['winter', 'holiday'];
      case DateTime.january:
      case DateTime.february:
        return const ['winter'];
      case DateTime.june:
      case DateTime.july:
      case DateTime.august:
        return const ['summer'];
      default:
        return const [];
    }
  }

  Future<bool> requestPermissionsIfNeeded() async {
    await initialize();
    if (kIsWeb) return true;

    if (Platform.isIOS || Platform.isMacOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final iosPermissions = await iosPlugin?.checkPermissions();
      if (iosPermissions?.isEnabled == true) {
        return true;
      }

      final iosGranted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      final macPlugin = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final macPermissions = await macPlugin?.checkPermissions();
      if (macPermissions?.isEnabled == true) {
        return true;
      }

      final macGranted = await macPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return iosGranted ?? macGranted ?? false;
    }

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final alreadyEnabled =
          await androidPlugin?.areNotificationsEnabled() ?? true;
      if (alreadyEnabled) {
        return true;
      }

      return await androidPlugin?.requestNotificationsPermission() ?? false;
    }

    return true;
  }

  Future<AndroidScheduleMode> _resolveAndroidScheduleMode() async {
    if (kIsWeb || !Platform.isAndroid) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canScheduleExact =
        await androidPlugin?.canScheduleExactNotifications() ?? false;
    if (canScheduleExact) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }

    // Exact alarms are restricted on newer Android versions. Fall back to an
    // inexact schedule instead of forcing the app into a fragile settings flow.
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  Future<void> scheduleExpiryReminder(Item item) async {
    await initialize();
    await cancelExpiryReminder(item.uuid);

    if (item.expiryDate == null || item.isArchived) return;

    final reminderDate = _morningOf(item.expiryDate!);
    if (reminderDate.isBefore(DateTime.now())) return;
    final scheduleMode = await _resolveAndroidScheduleMode();

    await _plugin.zonedSchedule(
      _expiryNotificationIdForItem(item.uuid),
      'Expiry Reminder',
      '${item.name} expires today.',
      tz.TZDateTime.from(reminderDate, tz.local),
      _expiryNotificationDetails(),
      androidScheduleMode: scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelExpiryReminder(String itemUuid) async {
    await initialize();
    await _plugin.cancel(_expiryNotificationIdForItem(itemUuid));
  }

  Future<void> scheduleLentReminder(Item item) async {
    await initialize();
    await cancelLentReminder(item.uuid);

    if (!item.isLent ||
        item.isArchived ||
        item.expectedReturnDate == null ||
        item.lentTo?.trim().isEmpty != false) {
      return;
    }

    final primaryAt = _morningOf(item.expectedReturnDate!);
    final scheduleMode = await _resolveAndroidScheduleMode();
    if (primaryAt.isAfter(DateTime.now())) {
      await _plugin.zonedSchedule(
        _lentNotificationIdForItem(item.uuid),
        'I Lent It Reminder',
        'Your ${item.name} is due back from ${item.lentTo!.trim()} today.',
        tz.TZDateTime.from(primaryAt, tz.local),
        _lentNotificationDetails(),
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    final followUpAt = primaryAt.add(const Duration(hours: 48));
    if (followUpAt.isAfter(DateTime.now())) {
      await _plugin.zonedSchedule(
        _lentFollowUpNotificationIdForItem(item.uuid),
        'Still waiting on a return?',
        '${item.name} was due back from ${item.lentTo!.trim()} two days ago.',
        tz.TZDateTime.from(followUpAt, tz.local),
        _lentNotificationDetails(),
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancelLentReminder(String itemUuid) async {
    await initialize();
    await _plugin.cancel(_lentNotificationIdForItem(itemUuid));
    await _plugin.cancel(_lentFollowUpNotificationIdForItem(itemUuid));
  }

  Future<void> showStillThereReminder(Item item) async {
    await initialize();
    await _plugin.show(
      NotificationConstants.stillThereBackgroundNotificationId,
      'Still there?',
      'You saved ${item.name} 6 months ago. Is it still in the ${item.locationName ?? 'same place'}?',
      _reminderNotificationDetails(),
    );
  }

  Future<void> showSeasonalReminder(
    Item item, {
    required int month,
  }) async {
    await initialize();
    final intro = switch (month) {
      DateTime.december => 'Winter is here!',
      DateTime.january || DateTime.february => 'Cold weather reminder!',
      DateTime.june || DateTime.july || DateTime.august =>
        'Summer is here!',
      _ => 'Seasonal reminder!',
    };

    await _plugin.show(
      NotificationConstants.seasonalBackgroundNotificationId,
      intro,
      'Time to dig out your ${item.name}.',
      _reminderNotificationDetails(),
    );
  }

  Future<void> rescheduleExpiryReminders(Iterable<Item> items) async {
    await initialize();
    for (final item in items) {
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
      await scheduleLentReminder(item);
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  DateTime _morningOf(DateTime date) {
    final target = DateTime(date.year, date.month, date.day, 9);
    if (!target.isBefore(DateTime.now())) return target;

    final today = DateTime.now();
    final sameDay = today.year == date.year &&
        today.month == date.month &&
        today.day == date.day;
    if (sameDay) {
      return today.add(const Duration(minutes: 1));
    }
    return target;
  }

  NotificationDetails _expiryNotificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationConstants.expiryChannelId,
        NotificationConstants.expiryChannelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  NotificationDetails _lentNotificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationConstants.lentChannelId,
        NotificationConstants.lentChannelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  NotificationDetails _reminderNotificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationConstants.reminderChannelId,
        NotificationConstants.reminderChannelName,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  int _expiryNotificationIdForItem(String uuid) {
    return (uuid.hashCode.abs() % 90000) +
        NotificationConstants.expiryNotificationIdBase;
  }

  int _lentNotificationIdForItem(String uuid) {
    return (uuid.hashCode.abs() % 90000) +
        NotificationConstants.lentNotificationIdBase;
  }

  int _lentFollowUpNotificationIdForItem(String uuid) {
    return (uuid.hashCode.abs() % 90000) +
        NotificationConstants.lentFollowUpNotificationIdBase;
  }
}
