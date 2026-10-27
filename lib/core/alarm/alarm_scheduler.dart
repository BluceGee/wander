import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';

/// 响铃事件（底层闹钟到点，含冷启动恢复补发）。
@immutable
class AlarmFiredEvent {
  const AlarmFiredEvent({required this.scheduleId, required this.recordId});

  final int scheduleId;

  /// 对应 [AlarmRecord.id]（通过 AlarmSettings.payload 回传）。
  final String recordId;

  @override
  bool operator ==(Object other) =>
      other is AlarmFiredEvent &&
      other.scheduleId == scheduleId &&
      other.recordId == recordId;

  @override
  int get hashCode => Object.hash(scheduleId, recordId);
}

/// 原生闹钟调度抽象：生产用 [PackageAlarmScheduler]（alarm 包），测试用假实现。
abstract class AlarmScheduler {
  /// 初始化底层内核（进程启动时调用一次）。
  Future<void> init();

  /// 注册到点闹钟；同 id 覆盖旧调度。返回是否注册成功。
  Future<bool> schedule({
    required int scheduleId,
    required DateTime triggerAt,
    required String recordId,
    required String ringtonePath,
    required String title,
    required String body,
    required bool vibrate,
  });

  /// 撤销调度（对正在响铃的闹钟等价于停止响铃）。
  Future<void> cancel(int scheduleId);

  /// 撤销全部调度。
  Future<void> cancelAll();

  /// 底层当前仍挂着的 scheduleId。
  Future<Set<int>> scheduledIds();

  /// 响铃流：到点时推送（含冷启动恢复补发）。
  Stream<AlarmFiredEvent> get onRang;

  /// 当前响铃 id 集合流：用于感知通知栏「停止」等不经应用的外部停止。
  Stream<Set<int>> get ringingIds;
}

/// 基于 alarm 5.x 的实现：
/// AlarmManager 精确调度 + 前台服务循环铃声 + 全屏响铃 + 重启补响。
class PackageAlarmScheduler implements AlarmScheduler {
  const PackageAlarmScheduler();

  @override
  Future<void> init() => Alarm.init();

  @override
  Future<bool> schedule({
    required int scheduleId,
    required DateTime triggerAt,
    required String recordId,
    required String ringtonePath,
    required String title,
    required String body,
    required bool vibrate,
  }) {
    return Alarm.set(
      alarmSettings: AlarmSettings(
        id: scheduleId,
        dateTime: triggerAt,
        // 'assets/...' 走内置资源；绝对路径走铃声副本（原生两种都支持）
        assetAudioPath: ringtonePath,
        loopAudio: true,
        vibrate: vibrate,
        warningNotificationOnKill: true,
        androidFullScreenIntent: true,
        allowAlarmOverlap: false,
        // 允许多个闹钟排在同一秒（比如两个 7:00 的闹钟）
        allowSameSecondScheduling: true,
        payload: recordId,
        notificationSettings: NotificationSettings(
          title: title,
          body: body,
          stopButton: '停止',
          // 不给原生「稍后提醒」按钮：贪睡次数/上限由响铃页统一记账
          androidStopAlarmOnDismiss: true,
        ),
        volumeSettings: const VolumeSettings.fixed(),
        androidStaleAfter: AlarmSettings.defaultStaleAfter,
      ),
    );
  }

  @override
  Future<void> cancel(int scheduleId) => Alarm.stop(scheduleId);

  @override
  Future<void> cancelAll() => Alarm.stopAll();

  @override
  Future<Set<int>> scheduledIds() async =>
      (await Alarm.getAlarms()).map((a) => a.id).toSet();

  @override
  Stream<AlarmFiredEvent> get onRang {
    // ringStream 在 alarm 5.x 已弃用；ringing 集合新增的 id 即「到点响铃」
    //（首次监听拿到的当前集合即冷启动恢复）。
    var previous = <int>{};
    return Alarm.ringing.expand((set) {
      final added = set.alarms
          .where((a) => !previous.contains(a.id))
          .map((a) => AlarmFiredEvent(scheduleId: a.id, recordId: a.payload ?? ''))
          .toList();
      previous = set.alarms.map((a) => a.id).toSet();
      return added;
    });
  }

  @override
  Stream<Set<int>> get ringingIds =>
      Alarm.ringing.map((set) => set.alarms.map((a) => a.id).toSet());
}
