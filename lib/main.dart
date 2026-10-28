import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/alarm/alarm_scheduler.dart';
import 'core/alarm/alarm_service.dart';
import 'core/storage/app_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 任何初始化失败/卡死都不能挡住 runApp —— 否则真机上表现为纯白启动屏卡死。
  AppStore? store;
  try {
    final prefs = await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 5));
    store = await AppStore.create(prefs).timeout(const Duration(seconds: 5));
  } catch (e, st) {
    debugPrint('本地状态初始化失败（重试一次）: $e\n$st');
    try {
      final prefs = await SharedPreferences.getInstance();
      store = await AppStore.create(prefs);
    } catch (e2, st2) {
      debugPrint('本地状态初始化重试仍失败: $e2\n$st2');
    }
  }
  if (store == null) {
    runApp(const _BootFailedApp());
    return;
  }

  final alarms = AlarmService(store, const PackageAlarmScheduler());
  try {
    // 闹钟内核：启动即补调度（重启/漏响恢复），并接管响铃事件
    await alarms.start().timeout(const Duration(seconds: 8));
  } catch (e, st) {
    debugPrint('闹钟内核启动失败（界面照常进入）: $e\n$st');
  }

  // release 下默认 ErrorWidget 是一块白板，异常无从得见；
  // 这里把异常直接画出来，白屏问题一眼可诊断。
  ErrorWidget.builder = (details) {
    final text = '${details.exception}';
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Text(
                '界面渲染出错：\n$text',
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  };

  runApp(XnlApp(store: store, alarms: alarms));
}

/// 本地状态彻底不可用时的兜底界面（不再白屏）。
class _BootFailedApp extends StatelessWidget {
  const _BootFailedApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('应用初始化失败：本地存储不可用，请尝试清除应用数据或重装。',
                style: TextStyle(fontSize: 15)),
          ),
        ),
      ),
    );
  }
}
