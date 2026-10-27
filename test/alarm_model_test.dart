import 'package:flutter_test/flutter_test.dart';
import 'package:xnl/core/models/alarm.dart';

void main() {
  group('AlarmRecord JSON', () {
    test('全字段序列化往返一致', () {
      final record = AlarmRecord.create(
        hour: 7,
        minute: 5,
        label: '起床',
        daysOfWeek: const [1, 3, 5],
        ringtonePath: '/data/user/0/xnl/files/ringtones/a.mp3',
        ringtoneName: '我的铃声',
        dismissMethod: AlarmDismissMethod.math,
        mathDifficulty: AlarmMathDifficulty.hard,
        mathQuestions: 4,
        holdSeconds: 6,
        typePhrase: '坚持',
        shakeCount: 15,
        vibrate: false,
        snoozeEnabled: true,
        snoozeMinutes: 12,
        snoozeLimit: 5,
      ).copyWith(snoozeCount: 2, snoozedUntil: DateTime(2026, 10, 27, 7, 17));

      final back = AlarmRecord.fromJson(record.toJson());
      expect(back.id, record.id);
      expect(back.label, '起床');
      expect(back.hour, 7);
      expect(back.minute, 5);
      expect(back.daysOfWeek, [1, 3, 5]);
      expect(back.isWeekly, isTrue);
      expect(back.ringtonePath, '/data/user/0/xnl/files/ringtones/a.mp3');
      expect(back.ringtoneName, '我的铃声');
      expect(back.dismissMethod, AlarmDismissMethod.math);
      expect(back.mathDifficulty, AlarmMathDifficulty.hard);
      expect(back.mathQuestions, 4);
      expect(back.holdSeconds, 6);
      expect(back.typePhrase, '坚持');
      expect(back.shakeCount, 15);
      expect(back.vibrate, isFalse);
      expect(back.snoozeEnabled, isTrue);
      expect(back.snoozeMinutes, 12);
      expect(back.snoozeLimit, 5);
      expect(back.snoozeCount, 2);
      expect(back.snoozedUntil, DateTime(2026, 10, 27, 7, 17));
      expect(back.createdAt, record.createdAt);
    });

    test('一次性日期往返与缺省容错', () {
      final record = AlarmRecord.create(
        hour: 8,
        minute: 30,
        date: DateTime(2026, 11, 1),
      );
      final back = AlarmRecord.fromJson(record.toJson());
      expect(back.date, DateTime(2026, 11, 1));
      expect(back.isOneShot, isTrue);

      final bare = AlarmRecord.fromJson({
        'id': '1',
        'hour': 25, // 越界 → 钳到 23
        'minute': -1, // 越界 → 钳到 0
        'createdAt': '2026-10-27T08:00:00.000',
      });
      expect(bare.hour, 23);
      expect(bare.minute, 0);
      expect(bare.ringtonePath, kDefaultRingtonePath);
      expect(bare.dismissMethod, AlarmDismissMethod.tap);
      expect(bare.isDaily, isTrue);
    });
  });

  group('AlarmRecord.nextTrigger', () {
    // 2026-10-27 是周二。
    final tue = DateTime(2026, 10, 27);

    test('每天：当天未到 / 已过则次日', () {
      final daily = AlarmRecord.create(hour: 7, minute: 0);
      expect(
        daily.nextTrigger(after: DateTime(2026, 10, 27, 6)),
        DateTime(2026, 10, 27, 7),
      );
      expect(
        daily.nextTrigger(after: DateTime(2026, 10, 27, 8)),
        DateTime(2026, 10, 28, 7),
      );
    });

    test('严格晚于参考时刻', () {
      final daily = AlarmRecord.create(hour: 7, minute: 0);
      expect(
        daily.nextTrigger(after: DateTime(2026, 10, 27, 7)),
        DateTime(2026, 10, 28, 7),
      );
    });

    test('每周：跳到下一个命中日', () {
      final weekly = AlarmRecord.create(hour: 7, minute: 0, daysOfWeek: const [3]);
      expect(
        weekly.nextTrigger(after: DateTime(2026, 10, 27, 6)),
        DateTime(2026, 10, 28, 7), // 周三
      );

      final sameDay = AlarmRecord.create(hour: 7, minute: 0, daysOfWeek: const [2]);
      expect(
        sameDay.nextTrigger(after: DateTime(2026, 10, 27, 6)),
        DateTime(2026, 10, 27, 7), // 周二当天
      );
      expect(
        sameDay.nextTrigger(after: DateTime(2026, 10, 27, 8)),
        DateTime(2026, 11, 3, 7), // 下周二
      );
    });

    test('一次性：未来响、过期不响', () {
      final future = AlarmRecord.create(hour: 8, minute: 0, date: tue);
      expect(future.nextTrigger(after: DateTime(2026, 10, 27, 6)), DateTime(2026, 10, 27, 8));

      final past = AlarmRecord.create(hour: 8, minute: 0, date: tue);
      expect(past.nextTrigger(after: DateTime(2026, 10, 27, 9)), isNull);
    });

    test('未启用不排', () {
      final off = AlarmRecord.create(hour: 7, minute: 0).copyWith(enabled: false);
      expect(off.nextTrigger(after: DateTime(2026, 10, 27, 6)), isNull);
    });
  });

  group('AlarmRecord.scheduleId', () {
    test('数字 id 直接解析', () {
      final record = AlarmRecord.create(hour: 7, minute: 0);
      expect(record.scheduleId, int.parse(record.id));
    });

    test('同一微秒连续 create 也唯一（防覆盖）', () {
      final ids = {
        for (var i = 0; i < 50; i++) AlarmRecord.create(hour: 7, minute: 0).id,
      };
      expect(ids, hasLength(50));
    });

    test('非数字 id 稳定映射（不用 hashCode）', () {
      AlarmRecord withId(String id) => AlarmRecord(
            id: id,
            hour: 7,
            minute: 0,
            createdAt: DateTime(2026),
          );
      expect(withId('abc').scheduleId, withId('abc').scheduleId);
      expect(withId('abc').scheduleId, isNot(withId('abd').scheduleId));
    });
  });

  group('AlarmRecord.copyWith', () {
    test('null 清除 date / snoozedUntil，其余保留', () {
      final record = AlarmRecord.create(
        hour: 7,
        minute: 0,
        date: DateTime(2026, 11, 1),
      ).copyWith(snoozedUntil: DateTime(2026, 11, 1, 7, 9), snoozeCount: 1);

      final cleared = record.copyWith(date: null, snoozedUntil: null, snoozeCount: 0);
      expect(cleared.date, isNull);
      expect(cleared.snoozedUntil, isNull);
      expect(cleared.snoozeCount, 0);
      expect(cleared.isDaily, isTrue);

      final kept = record.copyWith(label: 'x');
      expect(kept.date, DateTime(2026, 11, 1));
      expect(kept.snoozedUntil, DateTime(2026, 11, 1, 7, 9));
    });
  });
}
