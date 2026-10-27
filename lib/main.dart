import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/alarm/alarm_scheduler.dart';
import 'core/alarm/alarm_service.dart';
import 'core/storage/app_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final store = await AppStore.create(prefs);
  // 闹钟内核：启动即补调度（重启/漏响恢复），并接管响铃事件
  final alarms = AlarmService(store, const PackageAlarmScheduler());
  await alarms.start();
  runApp(XnlApp(store: store, alarms: alarms));
}
