/// 口语日期归一：把「今天 / 昨天 / 3号 / 上周三 / 10月1日」等解析为日期。
///
/// 解析失败返回 null，由调用方回传错误并附可选示例（不要瞎猜日期——
/// 猜错会把账记到错误的日期上）。成功时结果已归一为当天 0 点。
DateTime? tryParseDateHint(String raw, {DateTime? now}) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final base = now ?? DateTime.now();
  final today = DateTime(base.year, base.month, base.day);

  // YYYY-MM-DD / YYYY-M-D
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
  if (iso != null) {
    return _validated(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }

  // 相对日
  switch (text) {
    case '今天':
    case '今日':
      return today;
    case '昨天':
    case '昨日':
      return today.subtract(const Duration(days: 1));
    case '前天':
      return today.subtract(const Duration(days: 2));
    case '大前天':
      return today.subtract(const Duration(days: 3));
    case '明天':
    case '明日':
      return today.add(const Duration(days: 1));
    case '后天':
      return today.add(const Duration(days: 2));
    case '大后天':
      return today.add(const Duration(days: 3));
  }

  // N号 / N日：本月；若还没到（说「28号」而今天才 5 号）取上个月
  final dayOnly = RegExp(r'^(\d{1,2})[号日]$').firstMatch(text);
  if (dayOnly != null) {
    final day = int.parse(dayOnly.group(1)!);
    if (day < 1 || day > 31) return null;
    var candidate = DateTime(today.year, today.month, day);
    if (candidate.isAfter(today)) {
      candidate = DateTime(today.year, today.month - 1, day);
    }
    return _validated(candidate.year, candidate.month, candidate.day);
  }

  // M月D日 / M月D号
  final monthDay = RegExp(r'^(\d{1,2})月(\d{1,2})[号日]$').firstMatch(text);
  if (monthDay != null) {
    final month = int.parse(monthDay.group(1)!);
    final day = int.parse(monthDay.group(2)!);
    var candidate = _validated(today.year, month, day);
    if (candidate == null) return null;
    if (candidate.isAfter(today)) {
      candidate = _validated(today.year - 1, month, day);
    }
    return candidate;
  }

  // 周X / 星期X / 礼拜X（可带 上周/本周/这周 前缀）
  final week = RegExp(
    r'^(上|本|这)?(周|星期|礼拜)([一二三四五六日天])$',
  ).firstMatch(text);
  if (week != null) {
    const names = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    final target = names[week.group(3)!]!;
    final prefix = week.group(1);
    final thisMonday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    if (prefix == '上') {
      final lastMonday = thisMonday.subtract(const Duration(days: 7));
      return DateTime(lastMonday.year, lastMonday.month, lastMonday.day + (target - 1));
    }
    if (prefix == '本' || prefix == '这') {
      return DateTime(thisMonday.year, thisMonday.month, thisMonday.day + (target - 1));
    }
    // 无前缀：最近一个已过去的（含今天）
    var d = today;
    while (d.weekday != target) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  return null;
}

DateTime? _validated(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final d = DateTime(year, month, day);
  // DateTime 会把 2月30日 顺延成 3月2日，用回比对剔除
  if (d.year != year || d.month != month || d.day != day) return null;
  return d;
}
