import 'package:intl/intl.dart';

class TimeUtils {
  static DateTime beijingNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
  static String formatBeijing(DateTime time, {String pattern = 'HH:mm:ss'}) =>
      DateFormat(pattern, 'en_US').format(time.toUtc().add(const Duration(hours: 8)));

  static Duration? remaining(String time, DateTime now, {required num intimeDura}) {
    if (!intimeDura.isFinite || intimeDura <= 0) return null;
    final match = RegExp(r'^(\d{2}):(\d{2}):(\d{2})$').firstMatch(time);
    if (match == null) return null;
    final h = int.parse(match[1]!), m = int.parse(match[2]!), s = int.parse(match[3]!);
    if (h > 23 || m > 59 || s > 59) return null;
    final wall = now.toUtc().add(const Duration(hours: 8));
    var target = DateTime.utc(wall.year, wall.month, wall.day, h, m, s);
    // Only a late-night clock can roll into an early next-day service.
    if (target.isBefore(wall) && wall.hour >= 18 && h < 6) {
      target = target.add(const Duration(days: 1));
    }
    final delta = target.difference(wall);
    if (delta.isNegative || delta >= const Duration(hours: 6)) return null;
    return delta;
  }

  static String countdown(Duration duration) => duration.inMilliseconds <= 60000
      ? '即将到站' : '${(duration.inMilliseconds / 60000).ceil()} 分钟后';
}
