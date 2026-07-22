import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/media_service.dart';
import 'services/reminder_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  await MediaPaths.ensure();
  final state = AppState();
  await state.init();
  // 初始化本地通知，并按当前设置重新调度每日回顾提醒。
  await ReminderService.instance.init();
  await state.refreshReminder();
  runApp(
    ChangeNotifierProvider.value(value: state, child: const BabyApp()),
  );
}
