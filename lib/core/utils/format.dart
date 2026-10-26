import 'package:intl/intl.dart';

final _dateFmt = DateFormat('yyyy-MM-dd');
final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');
final _monthFmt = DateFormat('yyyy年MM月');

/// 2026-10-26
String formatDate(DateTime date) => _dateFmt.format(date);

/// 2026-10-26 14:30
String formatDateTime(DateTime date) => _dateTimeFmt.format(date);

/// 2026年10月
String formatMonth(DateTime date) => _monthFmt.format(date);

/// ¥1,234.56 —— 保留两位小数。
String formatMoney(double amount) {
  final fmt = NumberFormat.currency(locale: 'zh_CN', symbol: '¥', decimalDigits: 2);
  return fmt.format(amount);
}
