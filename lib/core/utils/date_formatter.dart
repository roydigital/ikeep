import 'package:intl/intl.dart';

final _dateFormat = DateFormat('dd MMM yyyy');
final _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');

/// Returns a human-readable relative time string.
/// e.g. "Just now", "2 hours ago", "3 days ago", "4 months ago".
String relativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);

  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '$h ${h == 1 ? 'hour' : 'hours'} ago';
  }
  if (diff.inDays < 30) {
    final d = diff.inDays;
    return '$d ${d == 1 ? 'day' : 'days'} ago';
  }
  if (diff.inDays < 365) {
    final m = (diff.inDays / 30).floor();
    return '$m ${m == 1 ? 'month' : 'months'} ago';
  }
  final y = (diff.inDays / 365).floor();
  return '$y ${y == 1 ? 'year' : 'years'} ago';
}

/// Formats a date for display in item cards (e.g. "15 Jan 2024").
String formatDate(DateTime dt) => _dateFormat.format(dt);

/// Formats a date + time (e.g. "15 Jan 2024, 02:30 PM").
String formatDateTime(DateTime dt) => _dateTimeFormat.format(dt);

/// Returns expiry urgency label.
/// - null if no expiry date
/// - "Expires today" / "Expires in X days" / "Expired X days ago"
String? formatExpiry(DateTime? expiryDate) {
  if (expiryDate == null) return null;
  final now = DateTime.now();
  final diff = expiryDate.difference(now);

  if (diff.isNegative) {
    final d = (-diff.inDays);
    return 'Expired ${d == 0 ? 'today' : '$d ${d == 1 ? 'day' : 'days'} ago'}';
  }
  if (diff.inDays == 0) return 'Expires today';
  return 'Expires in ${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'}';
}
