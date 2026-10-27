import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xnl/core/alarm/alarm_service.dart';
import 'package:xnl/core/models/alarm.dart';
import 'package:xnl/core/storage/app_store.dart';
import 'package:xnl/core/storage/key_vault.dart';

import 'fakes.dart';

void main() {
  late AppStore store;
  late FakeScheduler scheduler;
  late FakeClock clock;
  late AlarmService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = await AppStore.create(prefs, vault: InMemoryKeyVault());
    final built = buildFakeAlarmService(store);
    service = built.service;
    scheduler = built.scheduler;
    clock = built.clock;
    await service.start();
  });

  tearDown(() async {
    await service.dispose();
  });

  test('start 初始化底层；无记录时不排任何调度', () {
    expect(scheduler.initCalled, isTrue);
    expect(scheduler.scheduled, isEmpty);
  });

  test('save 启用的每天闹钟 → 排当天 7:00', () async {
    final record = AlarmRecord.create(hour: 7, minute: 0);
    await service.save(record);
    expect(scheduler.scheduled[record.scheduleId], DateTime(2026, 10, 27, 7));
    expect(store.alarmById(record.id), isNotNull);
  });

  test('save 停用的闹钟 → 不排', () async {
    final record = AlarmRecord.create(hour: 7, minute: 0).copyWith(enabled: false);
    await service.save(record);
    expect(scheduler.scheduled, isEmpty);
  });

  test('remove 撤销调度并删除记录', () async {
    final record = AlarmRecord.create(hour: 7, minute: 0);
    await service.save(record);
    await service.remove(record.id);
    expect(scheduler.scheduled, isEmpty);
    expect(store.alarmById(record.id), isNull);
  });

  test('关闭一次性响铃 → 停用且撤销调度', () async {
    final record = AlarmRecord.create(
      hour: 7,
      minute: 0,
      date: DateTime(2026, 10, 27),
    );
    await service.save(record);
    clock.now = DateTime(2026, 10, 27, 7);
    scheduler.fire(record.scheduleId);

    await service.stopRinging(store.alarmById(record.id)!);
    expect(store.alarmById(record.id)!.enabled, isFalse);
    expect(scheduler.scheduled, isEmpty);
  });

  test('关闭重复响铃 → 自动排下一次并清零贪睡计数', () async {
    final record = AlarmRecord.create(hour: 7, minute: 0);
    await service.save(record);
    clock.now = DateTime(2026, 10, 27, 7);
    scheduler.fire(record.scheduleId);

    await service.stopRinging(
      store.alarmById(record.id)!.copyWith(snoozeCount: 2),
    );
    final after = store.alarmById(record.id)!;
    expect(after.enabled, isTrue);
    expect(after.snoozeCount, 0);
    expect(scheduler.scheduled[record.scheduleId], DateTime(2026, 10, 28, 7));
  });

  test('贪睡：停响 + snoozeMinutes 再响，计数+1', () async {
    final record = AlarmRecord.create(hour: 7, minute: 0, snoozeMinutes: 9);
    await service.save(record);
    clock.now = DateTime(2026, 10, 27, 7);
    scheduler.fire(record.scheduleId);

    final ok = await service.snooze(store.alarmById(record.id)!);
    expect(ok, isTrue);
    final after = store.alarmById(record.id)!;
    expect(after.snoozeCount, 1);
    expect(after.snoozedUntil, DateTime(2026, 10, 27, 7, 9));
    expect(scheduler.scheduled[record.scheduleId], DateTime(2026, 10, 27, 7, 9));
  });

  test('贪睡达到上限 → 拒绝', () async {
    final record = AlarmRecord.create(
      hour: 7,
      minute: 0,
      snoozeMinutes: 5,
      snoozeLimit: 1,
    );
    await service.save(record);
    clock.now = DateTime(2026, 10, 27, 7);
    scheduler.fire(record.scheduleId);
    expect(await service.snooze(store.alarmById(record.id)!), isTrue);

    // 再次响铃后再贪睡 → 超上限
    clock.now = DateTime(2026, 10, 27, 7, 5);
    scheduler.fire(record.scheduleId);
    expect(await service.snooze(store.alarmById(record.id)!), isFalse);
  });

  test('通知栏停止（外部）→ 一次性同样停用，只记账一次', () async {
    final record = AlarmRecord.create(
      hour: 7,
      minute: 0,
      date: DateTime(2026, 10, 27),
    );
    await service.save(record);
    clock.now = DateTime(2026, 10, 27, 7);
    scheduler.fire(record.scheduleId);
    scheduler.stopExternally(record.scheduleId);
    await pumpEventQueue();

    final after = store.alarmById(record.id)!;
    expect(after.enabled, isFalse);
  });

  test('rescheduleAll：一次性漏响 5 分钟 → 补响', () async {
    final record = AlarmRecord.create(
      hour: 5,
      minute: 55,
      date: DateTime(2026, 10, 27),
    );
    await store.addAlarm(record);
    await service.rescheduleAll();

    final trigger = scheduler.scheduled[record.scheduleId]!;
    expect(trigger.difference(DateTime(2026, 10, 27, 6)).inSeconds, 2);
  });

  test('rescheduleAll：一次性漏响超过窗口 → 停用不补', () async {
    final record = AlarmRecord.create(
      hour: 7,
      minute: 0,
      date: DateTime(2026, 10, 26),
    );
    await store.addAlarm(record);
    await service.rescheduleAll();

    expect(scheduler.scheduled, isEmpty);
    expect(store.alarmById(record.id)!.enabled, isFalse);
  });

  test('rescheduleAll：贪睡未到期 → 以贪睡时刻为准', () async {
    final record = AlarmRecord.create(hour: 7, minute: 0).copyWith(
      snoozedUntil: DateTime(2026, 10, 27, 6, 30),
      snoozeCount: 1,
    );
    await store.addAlarm(record);
    await service.rescheduleAll();
    expect(scheduler.scheduled[record.scheduleId], DateTime(2026, 10, 27, 6, 30));
    expect(store.alarmById(record.id)!.snoozeCount, 1);
  });

  test('rescheduleAll：贪睡超时过久 → 清贪睡状态按自然时间', () async {
    final record = AlarmRecord.create(hour: 7, minute: 0).copyWith(
      snoozedUntil: DateTime(2026, 10, 27, 5, 0),
      snoozeCount: 1,
    );
    await store.addAlarm(record);
    await service.rescheduleAll();
    expect(scheduler.scheduled[record.scheduleId], DateTime(2026, 10, 27, 7));
    final after = store.alarmById(record.id)!;
    expect(after.snoozedUntil, isNull);
    expect(after.snoozeCount, 0);
  });

  test('rescheduleAll：清理无记录的孤儿调度', () async {
    await scheduler.schedule(
      scheduleId: 999,
      triggerAt: DateTime(2026, 10, 28),
      recordId: 'ghost',
      ringtonePath: kDefaultRingtonePath,
      title: 't',
      body: 'b',
      vibrate: true,
    );
    await service.rescheduleAll();
    expect(scheduler.scheduled, isEmpty);
  });

  test('AppStore 闹钟持久化往返 + clearAll 清空', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s1 = await AppStore.create(prefs, vault: InMemoryKeyVault());
    await s1.addAlarm(AlarmRecord.create(hour: 6, minute: 30, label: '晨跑'));
    await s1.addAlarm(AlarmRecord.create(hour: 22, minute: 0, label: '睡觉'));

    final s2 = await AppStore.create(prefs, vault: InMemoryKeyVault());
    expect(s2.alarms.length, 2);
    expect(s2.alarms.first.timeLabel, '06:30'); // 按时间排序

    await s2.clearAll();
    final s3 = await AppStore.create(prefs, vault: InMemoryKeyVault());
    expect(s3.alarms, isEmpty);
  });
}
