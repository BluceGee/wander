import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xnl/core/agent/agent_tool.dart';
import 'package:xnl/core/alarm/alarm_service.dart';
import 'package:xnl/core/models/alarm.dart';
import 'package:xnl/core/storage/app_store.dart';
import 'package:xnl/core/storage/key_vault.dart';
import 'package:xnl/features/assistant/app_tools.dart';
import 'package:xnl/features/assistant/assistant_store.dart';

import 'fakes.dart';

void main() {
  late AppStore store;
  late AlarmService alarms;
  late FakeScheduler scheduler;
  late List<AgentTool> tools;

  AgentTool tool(String name) => tools.firstWhere((t) => t.spec.name == name);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = await AppStore.create(prefs, vault: InMemoryKeyVault());
    final built = buildFakeAlarmService(store);
    alarms = built.service;
    scheduler = built.scheduler;
    await alarms.start();
    tools = buildAppTools(store, alarms);
  });

  group('create_alarm', () {
    test('「7点半」建成每天闹钟并排入调度', () async {
      final result = jsonDecode(await tool('create_alarm').execute({
        'time': '7点半',
        'label': '晨跑',
      })) as Map<String, dynamic>;

      expect(result['ok'], isTrue);
      expect(result['time'], '07:30');
      expect(result['repeat'], '每天');
      expect(result['label'], '晨跑');

      final record = store.alarms.single;
      expect(record.hour, 7);
      expect(record.minute, 30);
      expect(record.isDaily, isTrue);
      expect(scheduler.scheduled[record.scheduleId], DateTime(2026, 10, 27, 7, 30));
    });

    test('days 建成每周重复', () async {
      await tool('create_alarm').execute({
        'time': '21:00',
        'days': [1, 3, 5],
      });
      final record = store.alarms.single;
      expect(record.isWeekly, isTrue);
      expect(record.daysOfWeek, [1, 3, 5]);
    });

    test('date 建成一次性闹钟', () async {
      await tool('create_alarm').execute({
        'time': '8:00',
        'date': '2026-11-01',
      });
      final record = store.alarms.single;
      expect(record.isOneShot, isTrue);
      expect(record.date, DateTime(2026, 11, 1));
    });

    test('关闭方式与贪睡参数透传', () async {
      await tool('create_alarm').execute({
        'time': '6:00',
        'dismiss_method': 'math',
        'snooze_minutes': 5,
        'snooze_limit': 2,
      });
      final record = store.alarms.single;
      expect(record.dismissMethod, AlarmDismissMethod.math);
      expect(record.snoozeMinutes, 5);
      expect(record.snoozeLimit, 2);
    });

    test('非法参数报错（time/date+days/dismiss/snooze）', () async {
      await expectLater(
        tool('create_alarm').execute({'time': 'abc'}),
        throwsFormatException,
      );
      await expectLater(
        tool('create_alarm').execute({
          'time': '7:00',
          'date': '2026-11-01',
          'days': [1],
        }),
        throwsFormatException,
      );
      await expectLater(
        tool('create_alarm').execute({'time': '7:00', 'dismiss_method': 'x'}),
        throwsFormatException,
      );
      await expectLater(
        tool('create_alarm').execute({'time': '7:00', 'snooze_minutes': 0}),
        throwsFormatException,
      );
      expect(store.alarms, isEmpty);
    });
  });

  group('switch_alarm / delete_alarm', () {
    test('按 time 开关与删除', () async {
      await tool('create_alarm').execute({'time': '7点半'});
      final record = store.alarms.single;

      await tool('switch_alarm').execute({'time': '7点半', 'enabled': false});
      expect(store.alarmById(record.id)!.enabled, isFalse);
      expect(scheduler.scheduled, isEmpty);

      await tool('switch_alarm').execute({'id': record.id, 'enabled': true});
      expect(store.alarmById(record.id)!.enabled, isTrue);

      await tool('delete_alarm').execute({'time': '7点半'});
      expect(store.alarms, isEmpty);
      expect(scheduler.scheduled, isEmpty);
    });

    test('同刻多个闹钟按 time 删除要指明 id', () async {
      await tool('create_alarm').execute({'time': '7:00', 'label': 'a'});
      await tool('create_alarm').execute({'time': '7:00', 'label': 'b'});
      await expectLater(
        tool('delete_alarm').execute({'time': '7:00'}),
        throwsFormatException,
      );
      expect(store.alarms, hasLength(2));
    });

    test('找不到闹钟报错', () async {
      await expectLater(
        tool('delete_alarm').execute({'id': 'nope'}),
        throwsFormatException,
      );
      await expectLater(
        tool('switch_alarm').execute({'time': '3:33', 'enabled': true}),
        throwsFormatException,
      );
    });
  });

  group('list_alarms', () {
    test('返回开关、重复、下次响铃与关闭方式', () async {
      await tool('create_alarm').execute({'time': '7:30', 'label': '晨跑'});
      final result = jsonDecode(await tool('list_alarms').execute({}))
          as Map<String, dynamic>;
      expect(result['count'], 1);
      final item = (result['alarms'] as List).single as Map<String, dynamic>;
      expect(item['time'], '07:30');
      expect(item['enabled'], isTrue);
      expect(item['next_ring'], isNotNull);
      expect(item['dismiss'], '点一下');
    });
  });

  group('buildSystemPrompt', () {
    test('系统提示词提到全部工具名（新增工具别忘同步）', () {
      final prompt = AssistantStore(store, alarms).buildSystemPrompt();
      for (final t in tools) {
        expect(prompt, contains(t.spec.name), reason: '提示词缺少 ${t.spec.name}');
      }
    });
  });
}
