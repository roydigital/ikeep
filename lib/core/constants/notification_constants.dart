// Notification channel IDs, names, and notification IDs.
class NotificationConstants {
  NotificationConstants._();

  // Android channels
  static const String expiryChannelId = 'ikeep_expiry';
  static const String expiryChannelName = 'Expiry Reminders';
  static const String expiryChannelDesc =
      'Alerts when a stored item is approaching its expiry date';

  static const String reminderChannelId = 'ikeep_reminders';
  static const String reminderChannelName = 'Item Reminders';
  static const String reminderChannelDesc =
      'Periodic check-ins for old items (e.g. "Is this still there?")';

  static const String lentChannelId = 'ikeep_lent';
  static const String lentChannelName = 'I Lent It Reminders';
  static const String lentChannelDesc =
      'Reminders for items you lent to someone';

  static const String syncChannelId = 'ikeep_sync';
  static const String syncChannelName = 'Sync Status';
  static const String syncChannelDesc = 'Cloud sync status notifications';

  static const String updatesChannelId = 'ikeep_updates';
  static const String updatesChannelName = 'App Updates';
  static const String updatesChannelDesc =
      'Optional reminders when a Google Play update is available';

  // Notification ID strategy:
  // Expiry notifications use hash of itemUuid truncated to int range.
  // Reminder notifications use a fixed ID offset + index.
  static const int syncErrorNotificationId = 1;
  static const int stillThereBackgroundNotificationId = 2;
  static const int seasonalBackgroundNotificationId = 3;
  static const int expiryNotificationIdBase = 10000;
  static const int reminderNotificationIdBase = 20000;
  static const int lentNotificationIdBase = 30000;
  static const int lentFollowUpNotificationIdBase = 40000;
  static const int updateReminderNotificationId = 50001;
}
