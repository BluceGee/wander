import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:xnl/core/models/alarm.dart';
import 'package:xnl/features/alarm/math_problems.dart';

/// 按表达式重新计算，验证题面与答案一致。
int eval(String expression) {
  final parts = expression.split(' ');
  final a = int.parse(parts[0]);
  final b = int.parse(parts[2]);
  return switch (parts[1]) {
    '+' => a + b,
    '-' => a - b,
    '×' => a * b,
    _ => a ~/ b,
  };
}

void main() {
  group('generateMathProblem', () {
    for (final difficulty in AlarmMathDifficulty.values) {
      test('${difficulty.label}：100 道题面与答案一致且答案非负', () {
        final rnd = Random(42 + difficulty.index);
        for (var i = 0; i < 100; i++) {
          final p = generateMathProblem(difficulty, random: rnd);
          expect(eval(p.expression), p.answer, reason: p.expression);
          expect(p.answer, greaterThanOrEqualTo(0));
        }
      });
    }

    test('同种子可复现', () {
      final a = generateMathProblem(AlarmMathDifficulty.hard, random: Random(7));
      final b = generateMathProblem(AlarmMathDifficulty.hard, random: Random(7));
      expect(a, b);
    });

    test('简单题范围受限（和不超过 40）', () {
      final rnd = Random(1);
      for (var i = 0; i < 50; i++) {
        final p = generateMathProblem(AlarmMathDifficulty.easy, random: rnd);
        expect(p.answer, lessThanOrEqualTo(40));
      }
    });
  });
}
