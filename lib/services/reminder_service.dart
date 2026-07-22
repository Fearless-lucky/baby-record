import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/date_utils.dart';
import '../data/repositories.dart';

/// 每日回顾提醒：晚上 8 点本地通知，提醒为今天留一条记录。
///
/// - 完全本地调度，不联网；当天已有记录时自动跳过当晚提醒。
/// - 频率：0=从不，1=每天，2=仅周末。
class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  static const _dailyId = 7001;
  static const _weekendId = 7002;
  static const reminderHour = 20;

  /// 点击通知时由 app.dart 注册，用于跳转到"记录今天"。
  static void Function()? onOpenRecordToday;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == 'record_today') {
          onOpenRecordToday?.call();
        }
      },
    );
    _initialized = true;
  }

  /// Android 13+ 通知权限；返回是否已允许。
  Future<bool> ensurePermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final granted = await android.areNotificationsEnabled();
    if (granted == true) return true;
    return await android.requestNotificationsPermission() ?? false;
  }

  /// 按当前模式重新调度。每天打开 App / 保存记录 / 修改设置后调用。
  Future<void> refresh(int mode, String? babyId) async {
    await init();
    await _plugin.cancel(_dailyId);
    await _plugin.cancel(_weekendId);
    if (mode == 0 || babyId == null) return;

    // 当天已有记录时，今晚不再提醒，从下一个有效日开始调度。
    final now = DateTime.now();
    final today = AppDateUtils.day(now);
    final todayCount = await MomentRepository().count(
      babyId,
      filter: MomentFilter(from: today, to: today),
    );
    final skipToday = todayCount > 0;

    if (mode == 1) {
      var first = DateTime(today.year, today.month, today.day, reminderHour);
      if (!first.isAfter(now) || skipToday) {
        first = first.add(const Duration(days: 1));
      }
      await _schedule(
        id: _dailyId,
        at: first,
        match: DateTimeComponents.time,
        babyId: babyId,
      );
    } else {
      // 仅周末：找下一个周六或周日的 20 点。
      var day = today;
      for (var i = 0; i < 8; i++) {
        final isWeekend =
            day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
        var at = DateTime(day.year, day.month, day.day, reminderHour);
        final isToday = day == today;
        if (isWeekend && at.isAfter(now) && !(isToday && skipToday)) {
          await _schedule(
            id: _weekendId,
            at: at,
            match: DateTimeComponents.dayOfWeekAndTime,
            babyId: babyId,
          );
          return;
        }
        day = day.add(const Duration(days: 1));
      }
    }
  }

  Future<void> _schedule({
    required int id,
    required DateTime at,
    required DateTimeComponents match,
    required String babyId,
  }) async {
    await _plugin.zonedSchedule(
      id,
      '今天快过去了',
      '给今天留一张照片或一句话吧',
      tz.TZDateTime.from(at, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          '每日回顾提醒',
          channelDescription: '晚上提醒为今天留一条成长记录',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: match,
      payload: 'record_today',
    );
  }
}
