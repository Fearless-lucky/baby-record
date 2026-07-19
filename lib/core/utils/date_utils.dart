/// 日期与年龄相关的工具函数。
class AppDateUtils {
  AppDateUtils._();

  /// 将任意时间归一化到当天中午，避免时区/夏令时造成的边界问题。
  static DateTime day(DateTime dt) => DateTime(dt.year, dt.month, dt.day, 12);

  static DateTime fromMs(int ms) => day(DateTime.fromMillisecondsSinceEpoch(ms));

  static int toMs(DateTime dt) => day(dt).millisecondsSinceEpoch;

  /// yyyy年M月d日
  static String full(DateTime dt) => '${dt.year}年${dt.month}月${dt.day}日';

  /// yyyy/M/d
  static String compact(DateTime dt) => '${dt.year}/${dt.month}/${dt.day}';

  /// M月d日
  static String monthDay(DateTime dt) => '${dt.month}月${dt.day}日';

  /// yyyy年M月
  static String yearMonth(DateTime dt) => '${dt.year}年${dt.month}月';

  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static String weekday(DateTime dt) => _weekdays[dt.weekday - 1];

  /// 两个日期之间的整天数（b - a）。
  static int daysBetween(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return db.difference(da).inDays;
  }

  /// 宝宝出生后的第几天（出生当天为第 1 天）。
  static int dayOfLife(DateTime birth, DateTime date) =>
      daysBetween(birth, date) + 1;

  /// 年龄分解，例如 1岁2个月3天。
  static ({int years, int months, int days}) ageParts(DateTime birth, DateTime date) {
    var y = date.year - birth.year;
    var m = date.month - birth.month;
    var d = date.day - birth.day;
    if (d < 0) {
      m -= 1;
      final prevMonth = DateTime(date.year, date.month, 1);
      final daysInPrevMonth = prevMonth.subtract(const Duration(days: 1)).day;
      d += daysInPrevMonth;
    }
    if (m < 0) {
      y -= 1;
      m += 12;
    }
    return (years: y, months: m, days: d);
  }

  /// 简洁的年龄文案。
  static String ageText(DateTime birth, DateTime date) {
    final p = ageParts(birth, date);
    if (p.years > 0) {
      return p.months > 0 ? '${p.years}岁${p.months}个月' : '${p.years}岁';
    }
    if (p.months > 0) {
      return p.days > 0 ? '${p.months}个月${p.days}天' : '${p.months}个月';
    }
    return '${p.days}天';
  }

  /// 是否同月同日（用于"往年今日"）。
  static bool sameMonthDay(DateTime a, DateTime b) =>
      a.month == b.month && a.day == b.day;

  static DateTime monthStart(DateTime dt) => DateTime(dt.year, dt.month, 1, 12);

  static DateTime monthEnd(DateTime dt) =>
      DateTime(dt.year, dt.month + 1, 1, 12).subtract(const Duration(days: 1));

  static String two(int v) => v.toString().padLeft(2, '0');

  /// HH:mm
  static String time(DateTime dt) => '${two(dt.hour)}:${two(dt.minute)}';
}
