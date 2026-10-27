import 'dart:async';

import 'package:flutter/material.dart';

import 'core/alarm/alarm_service.dart';
import 'core/models/alarm.dart';
import 'core/storage/app_store.dart';
import 'core/theme/app_theme.dart';
import 'features/alarm/alarm_ring_page.dart';
import 'features/assistant/assistant_page.dart';
import 'features/auth/login_page.dart';

class XnlApp extends StatefulWidget {
  const XnlApp({super.key, required this.store, required this.alarms});

  final AppStore store;
  final AlarmService alarms;

  @override
  State<XnlApp> createState() => _XnlAppState();
}

class _XnlAppState extends State<XnlApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AlarmRecord>? _ringSub;

  /// 已在响铃页展示中的记录 id，防止同一记录重复叠页。
  final _ringingShown = <String>{};

  @override
  void initState() {
    super.initState();
    // 正常到点：响铃流推来记录就弹响铃页
    _ringSub = widget.alarms.onRing.listen(_pushRingPage);
    // 全屏意图拉起 / 启动时已在响的闹钟：首帧补弹
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final record in widget.alarms.ringingRecords) {
        _pushRingPage(record);
      }
    });
  }

  @override
  void dispose() {
    _ringSub?.cancel();
    super.dispose();
  }

  void _pushRingPage(AlarmRecord record) {
    if (_ringingShown.contains(record.id)) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return; // 首帧前的事件由启动检查补弹
    _ringingShown.add(record.id);
    navigator
        .push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AlarmRingPage(alarms: widget.alarms, record: record),
      ),
    )
        .then((_) => _ringingShown.remove(record.id));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'XNL 工具箱',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: widget.store.themeMode,
          // 打开即对话主页（豆包式）；首次启动先过欢迎/登录引导（可跳过）
          home: widget.store.welcomeDone
              ? AssistantPage(app: widget.store, alarms: widget.alarms)
              : LoginPage(store: widget.store),
        );
      },
    );
  }
}
