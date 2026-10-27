import 'package:flutter_test/flutter_test.dart';
import 'package:xnl/core/utils/clock_parse.dart';

void main() {
  group('tryParseClockTime', () {
    test('冒号格式', () {
      expect(tryParseClockTime('07:30'), (hour: 7, minute: 30));
      expect(tryParseClockTime('7:05'), (hour: 7, minute: 5));
      expect(tryParseClockTime('21:45'), (hour: 21, minute: 45));
      expect(tryParseClockTime('07：30'), (hour: 7, minute: 30)); // 全角冒号
    });

    test('点/半格式', () {
      expect(tryParseClockTime('7点'), (hour: 7, minute: 0));
      expect(tryParseClockTime('7点半'), (hour: 7, minute: 30));
      expect(tryParseClockTime('7点15'), (hour: 7, minute: 15));
      expect(tryParseClockTime('7点15分'), (hour: 7, minute: 15));
    });

    test('上下午修饰', () {
      expect(tryParseClockTime('晚上9点'), (hour: 21, minute: 0));
      expect(tryParseClockTime('晚上9点半'), (hour: 21, minute: 30));
      expect(tryParseClockTime('下午3点15'), (hour: 15, minute: 15));
      expect(tryParseClockTime('上午8点'), (hour: 8, minute: 0));
      expect(tryParseClockTime('早上7点30'), (hour: 7, minute: 30));
    });

    test('12 点的上下午边界', () {
      expect(tryParseClockTime('晚上12点'), (hour: 0, minute: 0));
      expect(tryParseClockTime('上午12点'), (hour: 0, minute: 0));
      expect(tryParseClockTime('中午12点'), (hour: 12, minute: 0));
    });

    test('无法识别返回 null', () {
      expect(tryParseClockTime(''), isNull);
      expect(tryParseClockTime('abc'), isNull);
      expect(tryParseClockTime('25:00'), isNull);
      expect(tryParseClockTime('7点99分'), isNull);
      expect(tryParseClockTime('下午'), isNull);
    });
  });
}
