import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xnl/app.dart';
import 'package:xnl/core/alarm/alarm_service.dart';
import 'package:xnl/core/models/alarm.dart';
import 'package:xnl/core/storage/app_store.dart';
import 'package:xnl/core/storage/key_vault.dart';
import 'package:xnl/features/alarm/alarm_ring_page.dart';

import 'fakes.dart';

void main() {
  late AppStore store;
  late AlarmService alarms;
  late FakeScheduler scheduler;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = await AppStore.create(prefs, vault: InMemoryKeyVault());
    final built = buildFakeAlarmService(store);
    alarms = built.service;
    scheduler = built.scheduler;
    await alarms.start();
  });

  Future<AlarmRecord> addAlarm({int hour = 7}) async {
    final record = AlarmRecord.create(
      hour: hour,
      minute: 0,
      date: DateTime(2026, 10, 28),
    );
    await alarms.save(record);
    return record;
  }

  testWidgets('闹钟到点：响铃页自动弹出，完成后关闭', (tester) async {
    final record = await addAlarm();
    await tester.pumpWidget(XnlApp(store: store, alarms: alarms));
    await tester.pumpAndSettle();
    expect(find.byType(AlarmRingPage), findsNothing);

    scheduler.fire(record.scheduleId);
    await tester.pumpAndSettle();
    expect(find.text('闹钟响了'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AlarmRingPage), findsNothing);
    expect(store.alarmById(record.id)!.enabled, isFalse); // 一次性响完即停
  });

  testWidgets('启动时已在响铃（全屏意图拉起）：首帧补弹响铃页', (tester) async {
    final record = await addAlarm();
    scheduler.fire(record.scheduleId); // 先响，UI 后启动
    await tester.pumpWidget(XnlApp(store: store, alarms: alarms));
    await tester.pumpAndSettle();

    expect(find.text('闹钟响了'), findsOneWidget);
  });

  testWidgets('两个闹钟先后到点：叠两层响铃页', (tester) async {
    final first = await addAlarm(hour: 6);
    final second = await addAlarm(hour: 7);
    await tester.pumpWidget(XnlApp(store: store, alarms: alarms));
    await tester.pumpAndSettle();

    scheduler.fire(first.scheduleId);
    await tester.pumpAndSettle();
    scheduler.fire(second.scheduleId);
    await tester.pumpAndSettle();

    // 底层路由 offstage，需 skipOffstage: false 才能数到两页
    expect(find.text('闹钟响了', skipOffstage: false), findsNWidgets(2));
  });

  testWidgets('同一闹钟响铃事件只弹一页', (tester) async {
    final record = await addAlarm();
    await tester.pumpWidget(XnlApp(store: store, alarms: alarms));
    await tester.pumpAndSettle();

    scheduler.fire(record.scheduleId);
    await tester.pumpAndSettle();
    scheduler.fire(record.scheduleId); // 重复事件
    await tester.pumpAndSettle();

    expect(find.byType(AlarmRingPage, skipOffstage: false), findsOneWidget);
  });
}
