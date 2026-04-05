import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants/notification_constants.dart';
import '../domain/models/item.dart';

/// Central notification service — the **only** entry point for all local
/// notification operations in the app.
///
/// ## Why this design?
///
/// The Android `flutter_local_notifications` plugin uses Gson internally to
/// serialize/deserialize scheduled notification payloads stored in
/// SharedPreferences. When Android R8/ProGuard strips generic type metadata,
/// Gson's `TypeToken` reflective instantiation fails with:
///
///   "TypeToken must be created with a type argument: new TypeToken<…>() {}"
///
/// This crash surfaces inside `loadScheduledNotifications()`, which the plugin
/// calls internally on *every* `cancel()`, `cancelAll()`, and `zonedSchedule()`
/// call. It can also happen when previously-scheduled notification payloads
/// become corrupted or incompatible after an app upgrade.
///
/// To prevent this from crashing any screen, every plugin call is wrapped with
/// [_safePlatformCall] which:
///   1. Ensures initialization has completed.
///   2. Catches `PlatformException` from the plugin.
///   3. On a Gson/TypeToken failure, performs a one-time nuclear recovery
///      (clears the plugin's internal scheduled-notification cache via
///      `cancelAll()`), then retries the original operation once.
///   4. If recovery also fails, logs the error and returns gracefully — the
///      app never crashes from a notification subsystem failure.
class NotificationService {
  factory NotificationService() => _instance;

  NotificationService._internal() : _plugin = FlutterLocalNotificationsPlugin();

  static final NotificationService _instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// Whether we have already attempted a nuclear cache recovery during this
  /// app session. We only attempt it once to avoid infinite retry loops.
  bool _cacheRecoveryAttempted = false;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

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
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          NotificationConstants.updatesChannelId,
          NotificationConstants.updatesChannelName,
          description: NotificationConstants.updatesChannelDesc,
          importance: Importance.defaultImportance,
        ),
      );
    }

    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Safe platform call wrapper
  // ---------------------------------------------------------------------------

  /// Wraps every plugin operation to guarantee:
  ///   - Plugin is initialized before any call.
  ///   - PlatformExceptions (especially Gson/TypeToken crashes) are caught.
  ///   - On a serialization-related crash, we attempt a one-time recovery by
  ///     clearing the plugin's corrupted scheduled-notification cache.
  ///   - The app never crashes from a notification subsystem failure.
  ///
  /// [operation] is the label used for debug logging.
  /// [action] is the actual plugin call to execute.
  /// [fallback] is the value returned if everything fails (defaults to null).
  Future<T?> _safePlatformCall<T>(
    String operation,
    Future<T> Function() action, {
    T? fallback,
  }) async {
    await initialize();

    try {
      return await action();
    } on PlatformException catch (e) {
      // Check if this is the known Gson/TypeToken serialization crash that
      // occurs when R8 strips generic signatures, or when the plugin's
      // internal SharedPreferences cache contains stale/corrupt payloads
      // from a previous app version.
      if (_isTypeTokenOrSerializationError(e)) {
        debugPrint(
          '[NotificationService] Gson/TypeToken crash during "$operation". '
          'Attempting recovery by clearing corrupted notification cache.',
        );
        return await _recoverAndRetry(operation, action, fallback: fallback);
      }

      // Non-serialization platform errors — log and swallow so the UI never
      // crashes from a notification subsystem failure.
      debugPrint(
        '[NotificationService] PlatformException during "$operation": '
        '${e.code} — ${e.message}',
      );
      return fallback;
    } catch (e) {
      // Catch-all for any unexpected errors (e.g. MissingPluginException on
      // platforms where the plugin is unavailable).
      debugPrint(
        '[NotificationService] Unexpected error during "$operation": $e',
      );
      return fallback;
    }
  }

  /// Returns `true` if the [PlatformException] looks like the Gson/TypeToken
  /// serialization crash that this service is specifically designed to survive.
  bool _isTypeTokenOrSerializationError(PlatformException e) {
    final message = '${e.code} ${e.message} ${e.details}'.toLowerCase();
    return message.contains('typetoken') ||
        message.contains('generic signatures') ||
        message.contains('gson') ||
        message.contains('loadschedulednotifications') ||
        message.contains('serializ');
  }

  /// Nuclear recovery: clears the plugin's internal scheduled-notification
  /// cache (which is the source of the corrupt data), then retries [action]
  /// once. If recovery itself fails, returns [fallback] silently.
  ///
  /// This runs at most once per app session to prevent infinite retry loops.
  Future<T?> _recoverAndRetry<T>(
    String operation,
    Future<T> Function() action, {
    T? fallback,
  }) async {
    if (_cacheRecoveryAttempted) {
      debugPrint(
        '[NotificationService] Cache recovery already attempted this session. '
        'Skipping retry for "$operation".',
      );
      return fallback;
    }

    _cacheRecoveryAttempted = true;

    try {
      // cancelAll() itself calls loadScheduledNotifications() internally,
      // which might also throw. If it does, we catch it and try the direct
      // SharedPreferences clear path below.
      await _plugin.cancelAll();
      debugPrint(
        '[NotificationService] cancelAll() succeeded — corrupt cache cleared.',
      );
    } on PlatformException catch (e2) {
      debugPrint(
        '[NotificationService] cancelAll() also failed during recovery: '
        '${e2.message}. Attempting direct SharedPreferences clear.',
      );
      // If even cancelAll() crashes, we try to clear the plugin's
      // SharedPreferences key directly. The plugin stores its scheduled
      // notification data under a known key. This is a last-resort measure.
      try {
        await _clearPluginScheduledNotificationCache();
      } catch (e3) {
        debugPrint(
          '[NotificationService] Direct cache clear also failed: $e3. '
          'Notification subsystem degraded but app will not crash.',
        );
        return fallback;
      }
    }

    // Retry the original operation now that the cache is cleared.
    try {
      return await action();
    } catch (retryError) {
      debugPrint(
        '[NotificationService] Retry of "$operation" failed after recovery: '
        '$retryError. Returning fallback.',
      );
      return fallback;
    }
  }

  /// Last-resort: directly clears the SharedPreferences key used by
  /// flutter_local_notifications to store scheduled notification payloads.
  ///
  /// The plugin uses the key "flutter_local_notifications" in the app's
  /// default SharedPreferences on Android. By clearing it, we wipe the
  /// corrupted Gson-serialized data that causes the TypeToken crash.
  ///
  /// Existing scheduled Android alarms will still fire (they're managed by
  /// AlarmManager), but the plugin won't be able to manage/cancel them.
  /// This is acceptable as a one-time recovery — new notifications will be
  /// scheduled fresh.
  Future<void> _clearPluginScheduledNotificationCache() async {
    if (kIsWeb || !Platform.isAndroid) return;

    // Use a platform channel to call SharedPreferences.edit().remove()
    // on the plugin's known storage key. We use MethodChannel because
    // the shared_preferences Flutter package uses a different mechanism.
    const channel = MethodChannel('com.roydigital.ikeep/notification_recovery');
    try {
      await channel.invokeMethod('clearScheduledNotificationCache');
    } on MissingPluginException {
      // The native handler isn't registered (e.g. older builds). Fall back
      // to the shared_preferences package approach.
      debugPrint(
        '[NotificationService] Native recovery channel not available. '
        'Cached scheduled notifications could not be cleared.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Static helpers
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Schedule mode resolution
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Expiry reminders
  // ---------------------------------------------------------------------------

  Future<void> scheduleExpiryReminder(Item item) async {
    await cancelExpiryReminder(item.uuid);

    if (item.expiryDate == null || item.isArchived) return;

    final reminderDate = _morningOf(item.expiryDate!);
    if (reminderDate.isBefore(DateTime.now())) return;
    final scheduleMode = await _resolveAndroidScheduleMode();

    await _safePlatformCall('scheduleExpiryReminder(${item.uuid})', () {
      return _plugin.zonedSchedule(
        _expiryNotificationIdForItem(item.uuid),
        'Expiry Reminder',
        '${item.name} expires today.',
        tz.TZDateTime.from(reminderDate, tz.local),
        _expiryNotificationDetails(),
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    });
  }

  Future<void> cancelExpiryReminder(String itemUuid) async {
    await _safePlatformCall(
      'cancelExpiryReminder($itemUuid)',
      () => _plugin.cancel(_expiryNotificationIdForItem(itemUuid)),
    );
  }

  // ---------------------------------------------------------------------------
  // Lent reminders
  // ---------------------------------------------------------------------------

  Future<void> scheduleLentReminder(Item item) async {
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
      await _safePlatformCall('scheduleLentReminder(${item.uuid})', () {
        return _plugin.zonedSchedule(
          _lentNotificationIdForItem(item.uuid),
          'I Lent It Reminder',
          'Your ${item.name} is due back from ${item.lentTo!.trim()} today.',
          tz.TZDateTime.from(primaryAt, tz.local),
          _lentNotificationDetails(),
          androidScheduleMode: scheduleMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      });
    }

    final followUpAt = primaryAt.add(const Duration(hours: 48));
    if (followUpAt.isAfter(DateTime.now())) {
      await _safePlatformCall(
        'scheduleLentFollowUp(${item.uuid})',
        () {
          return _plugin.zonedSchedule(
            _lentFollowUpNotificationIdForItem(item.uuid),
            'Still waiting on a return?',
            '${item.name} was due back from ${item.lentTo!.trim()} two days ago.',
            tz.TZDateTime.from(followUpAt, tz.local),
            _lentNotificationDetails(),
            androidScheduleMode: scheduleMode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        },
      );
    }
  }

  Future<void> cancelLentReminder(String itemUuid) async {
    await _safePlatformCall(
      'cancelLentReminder($itemUuid)',
      () => _plugin.cancel(_lentNotificationIdForItem(itemUuid)),
    );
    await _safePlatformCall(
      'cancelLentFollowUp($itemUuid)',
      () => _plugin.cancel(_lentFollowUpNotificationIdForItem(itemUuid)),
    );
  }

  // ---------------------------------------------------------------------------
  // Immediate show notifications (still-there & seasonal)
  // ---------------------------------------------------------------------------

  Future<void> showStillThereReminder(Item item) async {
    await _safePlatformCall('showStillThereReminder', () {
      return _plugin.show(
        NotificationConstants.stillThereBackgroundNotificationId,
        'Still there?',
        'You saved ${item.name} 6 months ago. Is it still in the '
            '${item.locationName ?? 'same place'}?',
        _reminderNotificationDetails(),
      );
    });
  }

  Future<void> showSeasonalReminder(
    Item item, {
    required int month,
  }) async {
    final intro = switch (month) {
      DateTime.december => 'Winter is here!',
      DateTime.january || DateTime.february => 'Cold weather reminder!',
      DateTime.june || DateTime.july || DateTime.august => 'Summer is here!',
      _ => 'Seasonal reminder!',
    };

    await _safePlatformCall('showSeasonalReminder', () {
      return _plugin.show(
        NotificationConstants.seasonalBackgroundNotificationId,
        intro,
        'Time to dig out your ${item.name}.',
        _reminderNotificationDetails(),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Batch operations
  // ---------------------------------------------------------------------------

  Future<void> rescheduleExpiryReminders(Iterable<Item> items) async {
    for (final item in items) {
      await scheduleExpiryReminder(item);
    }
  }

  Future<void> cancelExpiryReminders(Iterable<Item> items) async {
    for (final item in items) {
      await cancelExpiryReminder(item.uuid);
    }
  }

  Future<void> rescheduleLentReminders(Iterable<Item> items) async {
    for (final item in items) {
      await scheduleLentReminder(item);
    }
  }

  // ---------------------------------------------------------------------------
  // Update reminders
  // ---------------------------------------------------------------------------

  Future<void> scheduleUpdateReminder({
    required String title,
    required String body,
    required Duration after,
  }) async {
    final safeDelay =
        after < const Duration(minutes: 1) ? const Duration(minutes: 1) : after;
    final scheduleAt = DateTime.now().add(safeDelay);
    final scheduleMode = await _resolveAndroidScheduleMode();

    await _safePlatformCall('scheduleUpdateReminder', () {
      return _plugin.zonedSchedule(
        NotificationConstants.updateReminderNotificationId,
        title,
        body,
        tz.TZDateTime.from(scheduleAt, tz.local),
        _updateNotificationDetails(),
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    });
  }

  Future<void> cancelUpdateReminder() async {
    await _safePlatformCall(
      'cancelUpdateReminder',
      () => _plugin.cancel(NotificationConstants.updateReminderNotificationId),
    );
  }

  // ---------------------------------------------------------------------------
  // Cancel all — also wrapped for safety
  // ---------------------------------------------------------------------------

  Future<void> cancelAll() async {
    await _safePlatformCall(
      'cancelAll',
      () => _plugin.cancelAll(),
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

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

  NotificationDetails _updateNotificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationConstants.updatesChannelId,
        NotificationConstants.updatesChannelName,
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
