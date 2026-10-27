import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:xnl/core/alarm/alarm_service.dart';
import 'package:xnl/core/models/alarm.dart';
import 'package:xnl/core/storage/app_store.dart';
import 'package:xnl/core/storage/key_vault.dart';
import 'package:xnl/features/alarm/alarm_edit_page.dart';
import 'package:xnl/features/alarm/alarm_list_page.dart';
import 'package:xnl/features/alarm/alarm_permissions.dart';
import 'package:xnl/features/alarm/alarm_ring_page.dart';
import 'package:xnl/features/alarm/ringtone_picker.dart';

import 'fakes.dart';

/// 按题面算答案（与 math_problems_test 同一约定）。
int eval(String expression) {
  final parts = expression.split(' ');
  final a = int.parse(parts[0]);
  final b = int.parse(parts[2]);
  return switch (parts[1]) {
    '+' => a + b,
    '-' => a - b,
    '×' => a * b,
    _ => a ~/ b,
  };
}

void main() {
  late AppStore store;
  late AlarmService alarms;
  late FakeScheduler scheduler;

  setUp(() async {
    // 预置国产 ROM 引导标记，避免列表页测试被引导弹窗挡住
    SharedPreferences.setMockInitialValues({kAlarmVendorGuideKey: true});
    final prefs = await SharedPreferences.getInstance();
    store = await AppStore.create(prefs, vault: InMemoryKeyVault());
    final built = buildFakeAlarmService(store);
    alarms = built.service;
    scheduler = built.scheduler;
    await alarms.start();
  });

  Widget listPage() => MaterialApp(home: AlarmListPage(alarms: alarms));

  group('AlarmListPage', () {
    testWidgets('显示闹钟并可开关', (tester) async {
      await alarms.save(AlarmRecord.create(hour: 7, minute: 30, label: '晨跑'));
      await tester.pumpWidget(listPage());

      expect(find.text('07:30'), findsOneWidget);
      expect(find.textContaining('晨跑'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(store.alarms.single.enabled, isFalse);
      expect(scheduler.scheduled, isEmpty);
    });

    testWidgets('长按删除闹钟', (tester) async {
      final record = AlarmRecord.create(hour: 7, minute: 30);
      await alarms.save(record);
      await tester.pumpWidget(listPage());

      await tester.longPress(find.text('07:30'));
      await tester.pumpAndSettle();
      expect(find.text('删除闹钟？'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(store.alarms, isEmpty);
      expect(scheduler.scheduled, isEmpty);
    });

    testWidgets('空态提示', (tester) async {
      await tester.pumpWidget(listPage());
      expect(find.text('还没有闹钟'), findsOneWidget);
    });
  });

  group('AlarmEditPage', () {
    testWidgets('默认值直接保存 = 每天 7:00', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: AlarmEditPage(alarms: alarms)));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final record = store.alarms.single;
      expect(record.timeLabel, '07:00');
      expect(record.isDaily, isTrue);
      expect(scheduler.scheduled[record.scheduleId], isNotNull);
    });

    testWidgets('每周未选重复日时拦截', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: AlarmEditPage(alarms: alarms)));
      await tester.tap(find.text('每周'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.text('请至少选一个重复日'), findsOneWidget);
      expect(store.alarms, isEmpty);
    });

    testWidgets('一次性时间已过时拦截', (tester) async {
      final record = AlarmRecord.create(
        hour: 6,
        minute: 0,
        date: DateTime(2020, 1, 1),
      );
      await tester.pumpWidget(
          MaterialApp(home: AlarmEditPage(alarms: alarms, record: record)));
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.text('一次性闹钟的时间已过，请修改时间或日期'), findsOneWidget);
    });
  });

  group('AlarmRingPage', () {
    testWidgets('点一下关闭：一次性响铃后停用', (tester) async {
      final record = AlarmRecord.create(
        hour: 7,
        minute: 0,
        date: DateTime.now().add(const Duration(days: 1)),
      );
      await alarms.save(record);
      await tester.pumpWidget(MaterialApp(
          home: AlarmRingPage(alarms: alarms, record: record)));

      expect(find.text('闹钟响了'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '关闭'));
      await tester.pumpAndSettle();

      expect(store.alarmById(record.id)!.enabled, isFalse);
    });

    testWidgets('算题关闭：答对两道才停', (tester) async {
      final record = AlarmRecord.create(
        hour: 7,
        minute: 0,
        dismissMethod: AlarmDismissMethod.math,
        mathQuestions: 2,
      );
      await alarms.save(record);
      await tester.pumpWidget(MaterialApp(
          home: AlarmRingPage(alarms: alarms, record: record)));

      for (var i = 0; i < 2; i++) {
        final expression =
            tester.widget<Text>(find.textContaining('= ?')).data!;
        final answer = eval(expression.replaceFirst(' = ?', ''));
        await tester.enterText(find.byType(TextField), '$answer');
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();
      }

      // 每天闹钟：关闭后仍启用，并重新排到下一次（假时钟 06:00 → 今天 07:00）
      final after = store.alarmById(record.id)!;
      expect(after.enabled, isTrue);
      expect(scheduler.scheduled[record.scheduleId],
          DateTime(2026, 10, 27, 7));
    });

    testWidgets('输入文字关闭', (tester) async {
      final record = AlarmRecord.create(
        hour: 7,
        minute: 0,
        dismissMethod: AlarmDismissMethod.typing,
        typePhrase: '坚持就是胜利',
      );
      await alarms.save(record);
      await tester.pumpWidget(MaterialApp(
          home: AlarmRingPage(alarms: alarms, record: record)));

      await tester.enterText(find.byType(TextField), '不对');
      await tester.pump();
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '关闭'));
      expect(button.onPressed, isNull); // 未输对时不可点

      await tester.enterText(find.byType(TextField), '坚持就是胜利');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '关闭'));
      await tester.pumpAndSettle();

      expect(store.alarmById(record.id)!.enabled, isTrue); // 每天 → 排下一天
    });

    testWidgets('摇一摇关闭（注入数据流）', (tester) async {
      final record = AlarmRecord.create(
        hour: 7,
        minute: 0,
        dismissMethod: AlarmDismissMethod.shake,
        shakeCount: 2,
      );
      await alarms.save(record);
      final events = StreamController<UserAccelerometerEvent>();
      addTearDown(events.close);

      await tester.pumpWidget(MaterialApp(
        home: AlarmRingPage(
            alarms: alarms, record: record, shakeEvents: events.stream),
      ));
      expect(find.text('摇一摇手机 2 次关闭'), findsOneWidget);

      // 防抖是真实时钟，用 runAsync 推事件并真实等待
      await tester.runAsync(() async {
        for (var i = 0; i < 2; i++) {
          events.add(UserAccelerometerEvent(0, 0, 5, DateTime.now()));
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      });
      await tester.pumpAndSettle();

      expect(store.alarmById(record.id)!.enabled, isTrue);
    });

    testWidgets('贪睡：点贪睡后按 snoozeMinutes 再响', (tester) async {
      final record = AlarmRecord.create(
        hour: 7,
        minute: 0,
        snoozeMinutes: 9,
      );
      await alarms.save(record);
      await tester.pumpWidget(MaterialApp(
          home: AlarmRingPage(alarms: alarms, record: record)));

      await tester.tap(find.textContaining('贪睡 9 分钟'));
      await tester.pumpAndSettle();

      final after = store.alarmById(record.id)!;
      expect(after.snoozeCount, 1);
      expect(scheduler.scheduled[record.scheduleId],
          DateTime(2026, 10, 27, 6, 9)); // 假时钟 06:00 + 9 分钟
    });

    testWidgets('贪睡次数用完不再显示按钮', (tester) async {
      final record = AlarmRecord.create(hour: 7, minute: 0, snoozeLimit: 1)
          .copyWith(snoozeCount: 1);
      await alarms.save(record);
      await tester.pumpWidget(MaterialApp(
          home: AlarmRingPage(alarms: alarms, record: record)));

      expect(find.textContaining('贪睡'), findsNothing);
    });
  });

  group('showRingtonePicker', () {
    testWidgets('选择内置铃声', (tester) async {
      RingtoneChoice? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showRingtonePicker(
                  context,
                  current: const RingtoneChoice(
                      name: kDefaultRingtoneName,
                      path: kDefaultRingtonePath),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('选择铃声'), findsOneWidget);

      await tester.tap(find.text('温柔唤醒'));
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(picked!.name, '温柔唤醒');
      expect(picked!.path, 'assets/sounds/gentle.wav');
    });
  });
}
