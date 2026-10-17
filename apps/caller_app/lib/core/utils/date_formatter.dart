import 'package:intl/intl.dart';

/// Utility for formatting dates and durations
class DateFormatter {
  DateFormatter._();

  static String formatRelative(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24 && now.day == dateTime.day) {
      return 'Today at ${DateFormat('h:mm a').format(dateTime.toLocal())}';
    } else if (difference.inDays < 2) {
      return 'Yesterday at ${DateFormat('h:mm a').format(dateTime.toLocal())}';
    } else {
      return DateFormat('MMM d, h:mm a').format(dateTime.toLocal());
    }
  }

  static String formatFull(DateTime? dateTime) {
    if (dateTime == null) return 'N/A';
    return DateFormat('dd MMM yyyy, hh:mm a').format(dateTime.toLocal());
  }

  static String formatDuration(int seconds) {
    if (seconds <= 0) return '0s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) {
      return '${m}m ${s}s';
    }
    return '${s}s';
  }
}
