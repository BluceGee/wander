/// 口语时间归一：把「07:30 / 7点半 / 晚上9点15」等解析为时分。
///
/// 解析失败返回 null，由调用方回传错误并附可选示例（不要瞎猜时间）。
/// 只负责时间部分；日期（今天/明天/3号）由 date_hint.dart 处理。
({int hour, int minute})? tryParseClockTime(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s.replaceAll('：', ':');

  // 上下午修饰（「晚上12点」按 0 点处理）
  const pmWords = ['下午', '晚上', '傍晚', '晚间', '夜里', '夜晚'];
  const amWords = ['上午', '早上', '早晨', '清晨', '凌晨', '今早'];
  var pm = false;
  var night = false;
  var am = false;
  for (final w in pmWords) {
    if (s.contains(w)) {
      pm = true;
      night = night || w != '下午';
      s = s.replaceAll(w, '');
    }
  }
  for (final w in amWords) {
    if (s.contains(w)) {
      am = true;
      s = s.replaceAll(w, '');
    }
  }
  // 中性修饰（不改上下午）：「中午12点」就是 12:00
  for (final w in const ['中午', '正午']) {
    s = s.replaceAll(w, '');
  }
  s = s.trim();

  int? hour;
  int? minute;

  // HH:mm
  final colon = RegExp(r'^(\d{1,2})\s*:\s*(\d{1,2})$').firstMatch(s);
  if (colon != null) {
    hour = int.parse(colon.group(1)!);
    minute = int.parse(colon.group(2)!);
  } else {
    // H点 / H点半 / H点mm（分）
    final dian =
        RegExp(r'^(\d{1,2})\s*[点時时](?:\s*(\d{1,2})\s*分?|\s*(半))?$').firstMatch(s);
    if (dian != null) {
      hour = int.parse(dian.group(1)!);
      if (dian.group(3) != null) {
        minute = 30;
      } else {
        minute = int.parse(dian.group(2) ?? '0');
      }
    }
  }
  if (hour == null || minute == null) return null;

  // 上下午换算：下午/晚上 1~11 点 +12；「晚上12点」「上午12点」都是 0 点
  if (pm && hour < 12) hour += 12;
  if (hour == 12 && (am || night)) hour = 0;

  if (hour > 23 || minute > 59) return null;
  return (hour: hour, minute: minute);
}
