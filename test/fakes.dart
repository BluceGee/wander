import 'dart:async';

import 'package:xnl/core/alarm/alarm_scheduler.dart';
import 'package:xnl/core/alarm/alarm_service.dart';
import 'package:xnl/core/storage/app_store.dart';

/// 内存假调度器：记录调度、模拟到点/外部停止（测试专用）。
class FakeScheduler implements AlarmScheduler {
  final Map<int, DateTime> scheduled = {};
  final Map<int, String> recordIds = {};
  final Set<int> ringingNow = {};
  final _fired = StreamController<AlarmFiredEvent>.broadcast();
  final _ringingController = StreamController<Set<int>>.broadcast();
  bool initCalled = false;

  @override
  Future<void> init() async {
    initCalled = true;
  }

  @override
  Future<bool> schedule({
    required int scheduleId,
    required DateTime triggerAt,
    required String recordId,
    required String ringtonePath,
    required String title,
    required String body,
    required bool vibrate,
  }) async {
    scheduled[scheduleId] = triggerAt;
    recordIds[scheduleId] = recordId;
    return true;
  }

  @override
  Future<void> cancel(int scheduleId) async {
    scheduled.remove(scheduleId);
    recordIds.remove(scheduleId);
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
    recordIds.clear();
  }

  @override
  Future<Set<int>> scheduledIds() async => scheduled.keys.toSet();

  @override
  Stream<AlarmFiredEvent> get onRang => _fired.stream;

  @override
  Stream<Set<int>> get ringingIds => _ringingController.stream;

  /// 模拟底层到点响铃。
  void fire(int scheduleId) {
    ringingNow.add(scheduleId);
    _ringingController.add({...ringingNow});
    _fired.add(AlarmFiredEvent(
      scheduleId: scheduleId,
      recordId: recordIds[scheduleId] ?? '',
    ));
  }

  /// 模拟通知栏「停止」：响铃停、调度撤销，完全不经应用。
  void stopExternally(int scheduleId) {
    scheduled.remove(scheduleId);
    recordIds.remove(scheduleId);
    ringingNow.remove(scheduleId);
    _ringingController.add({...ringingNow});
  }
}

/// 可拨动的假时钟。
class FakeClock {
  FakeClock(this.now);
  DateTime now;
  DateTime call() => now;
}

/// 组装测试用 [AlarmService]（假调度器 + 假时钟，默认 2026-10-27 06:00）。
({AlarmService service, FakeScheduler scheduler, FakeClock clock})
    buildFakeAlarmService(AppStore store, {DateTime? start}) {
  final scheduler = FakeScheduler();
  final clock = FakeClock(start ?? DateTime(2026, 10, 27, 6));
  final service = AlarmService(store, scheduler, clock: clock.call);
  return (service: service, scheduler: scheduler, clock: clock);
}
