import 'dart:async';

import '../models/alarm.dart';
import '../storage/app_store.dart';
import 'alarm_scheduler.dart';

/// 闹钟编排：持久化（[AppStore]）+ 原生调度（[AlarmScheduler]）。
///
/// 负责：保存/删除/开关时同步调度；响铃后的关闭/贪睡记账；
/// 启动时补调度（重启、漏响、贪睡恢复、清理孤儿调度）。
///
/// 收尾规则（关闭响铃后）：
/// - 一次性闹钟 → 停用（响完即止）；
/// - 重复闹钟 → 自动排到下一次，贪睡计数清零。
///
/// 通知栏「停止」不经应用 UI，由响铃 id 集合流感知后走同一收尾，
/// 与应用内关闭共用 [_handled] 去重，保证只记账一次。
class AlarmService {
  AlarmService(
    this._store,
    this._scheduler, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppStore _store;
  final AlarmScheduler _scheduler;
  final DateTime Function() _clock;

  /// 持久化宿主（界面用它 ListenableBuilder 监听闹钟列表变化）。
  AppStore get store => _store;

  /// 漏响补响窗口：超过则视为错过，不再吵醒用户（与 alarm 包
  /// androidStaleAfter 默认值一致）。
  static const _catchUpWindow = Duration(minutes: 15);

  /// 补响留出的调度余量（AlarmManager 不接受“此刻”触发）。
  static const _catchUpDelay = Duration(seconds: 2);

  /// 同步广播：响铃事件即达响铃页，不依赖微任务队列
  ///（跨 zone 分发时异步广播可能把事件排到永远洗不到的队列里）。
  final _ringController = StreamController<AlarmRecord>.broadcast(sync: true);
  StreamSubscription<AlarmFiredEvent>? _firedSub;
  StreamSubscription<Set<int>>? _ringingSub;

  /// 底层当前处于响铃的 scheduleId。
  final Set<int> _ringing = {};

  /// 已由本服务收尾（关闭/贪睡/删除）的 scheduleId，防止重复记账。
  final Set<int> _handled = {};

  /// 响铃流：闹钟到点时推送对应记录（响铃页据此弹出）。
  Stream<AlarmRecord> get onRing => _ringController.stream;

  /// 当前正在响铃的记录（全屏意图拉起 / 启动时补弹响铃页用）。
  List<AlarmRecord> get ringingRecords {
    final result = <AlarmRecord>[];
    for (final sid in _ringing) {
      final record = _recordByScheduleId(sid);
      if (record != null) result.add(record);
    }
    return result;
  }

  /// 启动：接管响铃事件并补调度。幂等，可重复调用（如恢复前台时）。
  Future<void> start() async {
    await _scheduler.init();
    _firedSub ??= _scheduler.onRang.listen(_onFired);
    _ringingSub ??= _scheduler.ringingIds.listen(_onRingingChanged);
    await rescheduleAll();
  }

  Future<void> dispose() async {
    await _firedSub?.cancel();
    await _ringingSub?.cancel();
    _firedSub = null;
    _ringingSub = null;
  }

  /// 保存（新增/编辑/开关）并同步原生调度。
  Future<void> save(AlarmRecord record) async {
    if (_store.alarmById(record.id) == null) {
      await _store.addAlarm(record);
    } else {
      await _store.updateAlarm(record);
    }
    await _scheduleRecord(record);
  }

  /// 开关闹钟（开启时清掉历史贪睡状态）。
  Future<void> setEnabled(AlarmRecord record, bool enabled) {
    return save(
      record.copyWith(enabled: enabled, snoozedUntil: null, snoozeCount: 0),
    );
  }

  /// 删除并撤销调度。
  Future<void> remove(String id) async {
    final record = _store.alarmById(id);
    await _store.deleteAlarm(id);
    if (record != null) {
      _handled.add(record.scheduleId);
      await _scheduler.cancel(record.scheduleId);
    }
  }

  /// 关闭响铃（响铃页完成关闭挑战后调用）。
  Future<void> stopRinging(AlarmRecord record) async {
    final sid = record.scheduleId;
    _handled.add(sid);
    _ringing.remove(sid);
    await _scheduler.cancel(sid);
    await _finishRecord(record);
  }

  /// 贪睡：停响后 [AlarmRecord.snoozeMinutes] 分钟再响。
  ///
  /// 未启用贪睡或已达 [AlarmRecord.snoozeLimit] 上限返回 false。
  Future<bool> snooze(AlarmRecord record) async {
    if (!record.snoozeEnabled || record.snoozeCount >= record.snoozeLimit) {
      return false;
    }
    final sid = record.scheduleId;
    _handled.add(sid);
    _ringing.remove(sid);
    await _scheduler.cancel(sid);

    final until = _clock().add(Duration(minutes: record.snoozeMinutes));
    final updated =
        record.copyWith(snoozedUntil: until, snoozeCount: record.snoozeCount + 1);
    await _store.updateAlarm(updated);
    await _scheduler.schedule(
      scheduleId: sid,
      triggerAt: until,
      recordId: updated.id,
      ringtonePath: updated.ringtonePath,
      title: _titleOf(updated),
      body: _bodyOf(updated),
      vibrate: updated.vibrate,
    );
    return true;
  }

  /// 启动/恢复时对账：补调度、处理漏响、清理孤儿调度。幂等。
  Future<void> rescheduleAll() async {
    final active = <int>{};
    for (final record in _store.alarms) {
      active.add(record.scheduleId);
      await _scheduleRecord(record);
    }
    final orphans = await _scheduler.scheduledIds();
    for (final sid in orphans.difference(active)) {
      await _scheduler.cancel(sid);
    }
  }

  // ---------- 内部 ----------

  /// 停响后的记账：一次性→停用；重复→排下一次；贪睡状态清零。
  Future<void> _finishRecord(AlarmRecord record) async {
    final updated =
        record.copyWith(snoozedUntil: null, snoozeCount: 0, enabled: record.isOneShot ? false : record.enabled);
    await _store.updateAlarm(updated);
    if (updated.enabled) {
      await _scheduleRecord(updated);
    }
  }

  /// 通知栏「停止」等外部停止：与 [stopRinging] 同一记账，但不再撤销调度。
  Future<void> _handleImplicitStop(int scheduleId) async {
    _handled.add(scheduleId);
    final record = _recordByScheduleId(scheduleId);
    if (record == null) return;
    await _finishRecord(record);
  }

  void _onFired(AlarmFiredEvent event) {
    // 新一轮响铃开始，允许再次收尾
    _handled.remove(event.scheduleId);
    _ringing.add(event.scheduleId);
    final record = _store.alarmById(event.recordId);
    if (record != null) _ringController.add(record);
  }

  void _onRingingChanged(Set<int> ids) {
    final stopped = _ringing.difference(ids);
    _ringing
      ..removeAll(stopped)
      ..addAll(ids);
    for (final sid in stopped) {
      if (_handled.contains(sid)) continue;
      unawaited(_handleImplicitStop(sid));
    }
  }

  /// 按记录同步单个调度（含漏响补响/过期停用）。
  Future<void> _scheduleRecord(AlarmRecord record) async {
    final sid = record.scheduleId;
    if (!record.enabled) {
      await _scheduler.cancel(sid);
      return;
    }

    final now = _clock();
    DateTime? triggerAt;

    // 贪睡中的闹钟以 snoozedUntil 为准（一次性/重复通用）
    final pinned = record.snoozedUntil;
    if (pinned != null) {
      if (pinned.isAfter(now)) {
        triggerAt = pinned;
      } else if (now.difference(pinned) <= _catchUpWindow) {
        triggerAt = now.add(_catchUpDelay); // 贪睡漏响：补响
      } else {
        // 贪睡超时过久：清掉贪睡状态按自然规则处理
        record = record.copyWith(snoozedUntil: null, snoozeCount: 0);
        await _store.updateAlarm(record);
      }
    }

    triggerAt ??= record.nextTrigger(after: now);
    if (triggerAt == null && record.isOneShot) {
      final nominal = record.nominalTrigger!;
      if (now.difference(nominal) <= _catchUpWindow && !nominal.isAfter(now)) {
        triggerAt = now.add(_catchUpDelay); // 一次性漏响：窗口内补响
      } else {
        // 窗口外过期：停用，保留记录供查看
        await _scheduler.cancel(sid);
        await _store.updateAlarm(record.copyWith(enabled: false));
        return;
      }
    }
    if (triggerAt == null) {
      await _scheduler.cancel(sid);
      return;
    }

    await _scheduler.schedule(
      scheduleId: sid,
      triggerAt: triggerAt,
      recordId: record.id,
      ringtonePath: record.ringtonePath,
      title: _titleOf(record),
      body: _bodyOf(record),
      vibrate: record.vibrate,
    );
  }

  AlarmRecord? _recordByScheduleId(int scheduleId) {
    for (final record in _store.alarms) {
      if (record.scheduleId == scheduleId) return record;
    }
    return null;
  }

  String _titleOf(AlarmRecord record) =>
      record.label.trim().isEmpty ? '闹钟' : record.label.trim();

  String _bodyOf(AlarmRecord record) =>
      '${record.timeLabel} · ${record.dismissMethod.label}关闭';
}
