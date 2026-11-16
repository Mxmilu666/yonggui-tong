import 'package:intl/intl.dart';

class TimeUtils {
  static DateTime beijingNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
  static String formatBeijing(DateTime time, {String pattern = 'HH:mm:ss'}) =>
      DateFormat(pattern, 'en_US').format(time.toUtc().add(const Duration(hours: 8)));

  /// A Beijing clock on [day]'s date, returned as a UTC instant.
  static DateTime? clockOnDay(String time, DateTime day) {
    final match = RegExp(r'^(\d{2}):(\d{2}):(\d{2})$').firstMatch(time);
    if (match == null) return null;
    final h = int.parse(match[1]!), m = int.parse(match[2]!), s = int.parse(match[3]!);
    if (h > 23 || m > 59 || s > 59) return null;
    final wall = day.toUtc().add(const Duration(hours: 8));
    return DateTime.utc(wall.year, wall.month, wall.day, h, m, s).subtract(const Duration(hours: 8));
  }

  /// Resolve a future departure against the snapshot, never against the moving display clock.
  static DateTime? departure(String time, DateTime observedAt) {
    var target = clockOnDay(time, observedAt);
    if (target == null) return null;
    final wall = observedAt.toUtc().add(const Duration(hours: 8));
    final targetHour = target.add(const Duration(hours: 8)).hour;
    if (target.isBefore(observedAt) && wall.hour >= 18 && targetHour < 6) {
      target = target.add(const Duration(days: 1));
    }
    final delta = target.difference(observedAt);
    if (delta.isNegative || delta >= const Duration(hours: 6)) return null;
    return target;
  }

  static String countdown(Duration duration, {bool showSeconds = false}) {
    if (duration <= Duration.zero) return '停靠中';
    if (showSeconds) {
      final seconds = (duration.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/ Duration.microsecondsPerSecond;
      return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    }
    return duration.inMilliseconds <= 60000 ? '即将到站' : '${(duration.inMilliseconds / 60000).ceil()} 分钟后';
  }
}
