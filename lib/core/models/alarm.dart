import 'package:flutter/foundation.dart';

/// 关闭闹钟的方式（自定义「怎么关闭」）。
enum AlarmDismissMethod {
  /// 点一下关闭。
  tap,

  /// 长按按钮若干秒关闭。
  hold,

  /// 算对若干道算术题才关闭。
  math,

  /// 输入指定文字才关闭。
  typing,

  /// 摇一摇若干次关闭。
  shake,
}

/// 算术题难度。
enum AlarmMathDifficulty {
  easy,
  medium,
  hard,
}

extension AlarmDismissMethodLabel on AlarmDismissMethod {
  /// 中文名（UI 与 agent 工具共用）。
  String get label => switch (this) {
        AlarmDismissMethod.tap => '点一下',
        AlarmDismissMethod.hold => '长按',
        AlarmDismissMethod.math => '算题',
        AlarmDismissMethod.typing => '输入文字',
        AlarmDismissMethod.shake => '摇一摇',
      };
}

extension AlarmMathDifficultyLabel on AlarmMathDifficulty {
  /// 中文名（UI 与 agent 工具共用）。
  String get label => switch (this) {
        AlarmMathDifficulty.easy => '简单',
        AlarmMathDifficulty.medium => '中等',
        AlarmMathDifficulty.hard => '困难',
      };
}

/// 内置铃声（assets 下程序合成的 WAV）。
@immutable
class BuiltinRingtone {
  const BuiltinRingtone({required this.name, required this.assetPath});

  final String name;
  final String assetPath;
}

/// 内置铃声清单（顺序即选择器展示顺序）。
const kBuiltinRingtones = <BuiltinRingtone>[
  BuiltinRingtone(name: '经典蜂鸣', assetPath: 'assets/sounds/classic.wav'),
  BuiltinRingtone(name: '温柔唤醒', assetPath: 'assets/sounds/gentle.wav'),
  BuiltinRingtone(name: '急促双响', assetPath: 'assets/sounds/urgent.wav'),
  BuiltinRingtone(name: '上行铃音', assetPath: 'assets/sounds/melody.wav'),
];

/// 默认铃声。
const kDefaultRingtonePath = 'assets/sounds/classic.wav';
const kDefaultRingtoneName = '经典蜂鸣';

/// 闹钟条目。
///
/// 重复语义：
/// - [date] 非空 → 一次性闹钟（响完即停用）；
/// - [date] 为空且 [daysOfWeek] 非空 → 每周选定日重复（1=周一 … 7=周日）；
/// - [date] 为空且 [daysOfWeek] 为空 → 每天重复。
///
/// [ringtonePath] 为 `assets/...` 时是内置铃声，绝对路径时是用户铃声副本
/// （响铃时原生两种都支持）。
@immutable
class AlarmRecord {
  const AlarmRecord({
    required this.id,
    required this.hour,
    required this.minute,
    required this.createdAt,
    this.label = '',
    this.date,
    this.daysOfWeek = const [],
    this.enabled = true,
    this.ringtonePath = kDefaultRingtonePath,
    this.ringtoneName = kDefaultRingtoneName,
    this.dismissMethod = AlarmDismissMethod.tap,
    this.mathDifficulty = AlarmMathDifficulty.easy,
    this.mathQuestions = 2,
    this.holdSeconds = 3,
    this.typePhrase = '起床啦',
    this.shakeCount = 10,
    this.vibrate = true,
    this.snoozeEnabled = true,
    this.snoozeMinutes = 9,
    this.snoozeLimit = 3,
    this.snoozeCount = 0,
    this.snoozedUntil,
  })  : assert(hour >= 0 && hour < 24),
        assert(minute >= 0 && minute < 60);

  /// 自增护栏：同一微秒内连续 create 也能拿到唯一 id
  ///（工具连发闹钟时会撞微秒，撞了会让后一条当成前一条的更新）。
  static int _lastId = 0;

  /// 新建闹钟（id 为微秒时间戳字符串，跨运行稳定）。
  factory AlarmRecord.create({
    required int hour,
    required int minute,
    String label = '',
    DateTime? date,
    List<int> daysOfWeek = const [],
    bool enabled = true,
    String ringtonePath = kDefaultRingtonePath,
    String ringtoneName = kDefaultRingtoneName,
    AlarmDismissMethod dismissMethod = AlarmDismissMethod.tap,
    AlarmMathDifficulty mathDifficulty = AlarmMathDifficulty.easy,
    int mathQuestions = 2,
    int holdSeconds = 3,
    String typePhrase = '起床啦',
    int shakeCount = 10,
    bool vibrate = true,
    bool snoozeEnabled = true,
    int snoozeMinutes = 9,
    int snoozeLimit = 3,
  }) {
    final now = DateTime.now();
    var id = now.microsecondsSinceEpoch;
    if (id <= _lastId) id = _lastId + 1;
    _lastId = id;
    return AlarmRecord(
      id: '$id',
      hour: hour,
      minute: minute,
      createdAt: now,
      label: label,
      date: date,
      daysOfWeek: daysOfWeek,
      enabled: enabled,
      ringtonePath: ringtonePath,
      ringtoneName: ringtoneName,
      dismissMethod: dismissMethod,
      mathDifficulty: mathDifficulty,
      mathQuestions: mathQuestions,
      holdSeconds: holdSeconds,
      typePhrase: typePhrase,
      shakeCount: shakeCount,
      vibrate: vibrate,
      snoozeEnabled: snoozeEnabled,
      snoozeMinutes: snoozeMinutes,
      snoozeLimit: snoozeLimit,
    );
  }

  final String id;
  final String label;
  final int hour;
  final int minute;

  /// 一次性闹钟的日期（null 表示重复闹钟）。
  final DateTime? date;

  /// 每周重复日（1=周一 … 7=周日；仅重复闹钟使用）。
  final List<int> daysOfWeek;
  final bool enabled;

  /// 铃声：`assets/...` = 内置；绝对路径 = 用户铃声副本。
  final String ringtonePath;
  final String ringtoneName;

  /// 关闭方式与参数。
  final AlarmDismissMethod dismissMethod;
  final AlarmMathDifficulty mathDifficulty;
  final int mathQuestions;
  final int holdSeconds;
  final String typePhrase;
  final int shakeCount;

  final bool vibrate;

  /// 贪睡（自定义「暂时关闭后多长时间再响」）。
  final bool snoozeEnabled;
  final int snoozeMinutes;

  /// 最多贪睡次数。
  final int snoozeLimit;

  /// 本次响铃周期内已贪睡次数。
  final int snoozeCount;

  /// 贪睡后的再响时刻（null = 无进行中的贪睡）。
  final DateTime? snoozedUntil;

  final DateTime createdAt;

  /// 一次性闹钟。
  bool get isOneShot => date != null;

  /// 每天重复。
  bool get isDaily => date == null && daysOfWeek.isEmpty;

  /// 每周选定日重复。
  bool get isWeekly => date == null && daysOfWeek.isNotEmpty;

  /// 「07:05」形式的时间标签。
  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// 一次性闹钟的名义触发时刻（重复闹钟为 null）。
  DateTime? get nominalTrigger {
    final d = date;
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  /// 映射到 alarm 包的 int id。
  ///
  /// 必须落在 32 位有符号正数范围内：alarm 包对超界的 id 直接抛
  /// AlarmException（启动补调度时抛出会挡住 runApp，表现为纯白屏卡死）。
  /// 微秒 id（≈1.8e15）不能直接解析使用——既超上限，简单掩码又会约
  /// 35.8 分钟一撞；因此统一走确定性 FNV-1a 哈希掩到 31 位
  /// （跨运行稳定，不能用 String.hashCode）。
  int get scheduleId {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash; // 0 / -1 是 alarm 包的非法 id
  }

  /// 下一次响铃时刻（严格晚于 [after]，默认现在）；不会响则返回 null。
  ///
  /// 未启用、一次性闹钟已过期均返回 null。贪睡中的 [snoozedUntil]
  /// 不在这里生效，由 AlarmService 统一处理。
  DateTime? nextTrigger({DateTime? after}) {
    if (!enabled) return null;
    final ref = after ?? DateTime.now();
    if (date != null) {
      final t = nominalTrigger!;
      return t.isAfter(ref) ? t : null;
    }
    if (daysOfWeek.isEmpty) {
      var t = DateTime(ref.year, ref.month, ref.day, hour, minute);
      if (!t.isAfter(ref)) t = t.add(const Duration(days: 1));
      return t;
    }
    for (var i = 0; i < 8; i++) {
      final d = ref.add(Duration(days: i));
      if (!daysOfWeek.contains(d.weekday)) continue;
      final t = DateTime(d.year, d.month, d.day, hour, minute);
      if (t.isAfter(ref)) return t;
    }
    return null;
  }

  factory AlarmRecord.fromJson(Map<String, dynamic> json) {
    int clampInt(Object? v, int min, int max, int fallback) {
      final n = (v as num?)?.toInt() ?? fallback;
      return n.clamp(min, max);
    }

    return AlarmRecord(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      hour: clampInt(json['hour'], 0, 23, 0),
      minute: clampInt(json['minute'], 0, 59, 0),
      date: json['date'] == null ? null : DateTime.parse(json['date'] as String),
      daysOfWeek: ((json['daysOfWeek'] as List?) ?? const [])
          .map((e) => clampInt(e, 1, 7, 1))
          .toList(),
      enabled: json['enabled'] as bool? ?? true,
      ringtonePath: json['ringtonePath'] as String? ?? kDefaultRingtonePath,
      ringtoneName: json['ringtoneName'] as String? ?? kDefaultRingtoneName,
      dismissMethod: AlarmDismissMethod.values.firstWhere(
        (e) => e.name == json['dismissMethod'],
        orElse: () => AlarmDismissMethod.tap,
      ),
      mathDifficulty: AlarmMathDifficulty.values.firstWhere(
        (e) => e.name == json['mathDifficulty'],
        orElse: () => AlarmMathDifficulty.easy,
      ),
      mathQuestions: clampInt(json['mathQuestions'], 1, 9, 2),
      holdSeconds: clampInt(json['holdSeconds'], 1, 30, 3),
      typePhrase: json['typePhrase'] as String? ?? '起床啦',
      shakeCount: clampInt(json['shakeCount'], 1, 50, 10),
      vibrate: json['vibrate'] as bool? ?? true,
      snoozeEnabled: json['snoozeEnabled'] as bool? ?? true,
      snoozeMinutes: clampInt(json['snoozeMinutes'], 1, 60, 9),
      snoozeLimit: clampInt(json['snoozeLimit'], 0, 20, 3),
      snoozeCount: clampInt(json['snoozeCount'], 0, 20, 0),
      snoozedUntil: json['snoozedUntil'] == null
          ? null
          : DateTime.parse(json['snoozedUntil'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hour': hour,
        'minute': minute,
        'date': date?.toIso8601String(),
        'daysOfWeek': daysOfWeek,
        'enabled': enabled,
        'ringtonePath': ringtonePath,
        'ringtoneName': ringtoneName,
        'dismissMethod': dismissMethod.name,
        'mathDifficulty': mathDifficulty.name,
        'mathQuestions': mathQuestions,
        'holdSeconds': holdSeconds,
        'typePhrase': typePhrase,
        'shakeCount': shakeCount,
        'vibrate': vibrate,
        'snoozeEnabled': snoozeEnabled,
        'snoozeMinutes': snoozeMinutes,
        'snoozeLimit': snoozeLimit,
        'snoozeCount': snoozeCount,
        'snoozedUntil': snoozedUntil?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  static const _unset = Object();

  /// 复制并修改字段；[date] / [snoozedUntil] 传 null 表示清除。
  AlarmRecord copyWith({
    String? label,
    int? hour,
    int? minute,
    Object? date = _unset,
    List<int>? daysOfWeek,
    bool? enabled,
    String? ringtonePath,
    String? ringtoneName,
    AlarmDismissMethod? dismissMethod,
    AlarmMathDifficulty? mathDifficulty,
    int? mathQuestions,
    int? holdSeconds,
    String? typePhrase,
    int? shakeCount,
    bool? vibrate,
    bool? snoozeEnabled,
    int? snoozeMinutes,
    int? snoozeLimit,
    int? snoozeCount,
    Object? snoozedUntil = _unset,
  }) {
    return AlarmRecord(
      id: id,
      label: label ?? this.label,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      date: identical(date, _unset) ? this.date : date as DateTime?,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      enabled: enabled ?? this.enabled,
      ringtonePath: ringtonePath ?? this.ringtonePath,
      ringtoneName: ringtoneName ?? this.ringtoneName,
      dismissMethod: dismissMethod ?? this.dismissMethod,
      mathDifficulty: mathDifficulty ?? this.mathDifficulty,
      mathQuestions: mathQuestions ?? this.mathQuestions,
      holdSeconds: holdSeconds ?? this.holdSeconds,
      typePhrase: typePhrase ?? this.typePhrase,
      shakeCount: shakeCount ?? this.shakeCount,
      vibrate: vibrate ?? this.vibrate,
      snoozeEnabled: snoozeEnabled ?? this.snoozeEnabled,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      snoozeLimit: snoozeLimit ?? this.snoozeLimit,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      snoozedUntil: identical(snoozedUntil, _unset)
          ? this.snoozedUntil
          : snoozedUntil as DateTime?,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) => other is AlarmRecord && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
