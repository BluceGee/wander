import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/models/alarm.dart';

/// 一道算术题（表达式 + 答案）。
@immutable
class MathProblem {
  const MathProblem(this.expression, this.answer);

  /// 展示给用户的表达式，如「12 + 7」。
  final String expression;

  final int answer;

  @override
  bool operator ==(Object other) =>
      other is MathProblem &&
      other.expression == expression &&
      other.answer == answer;

  @override
  int get hashCode => Object.hash(expression, answer);
}

/// 生成一道算术题：难度决定运算与数值范围（负数不出现，答案非负）。
MathProblem generateMathProblem(AlarmMathDifficulty difficulty, {Random? random}) {
  final rnd = random ?? Random();
  return switch (difficulty) {
    AlarmMathDifficulty.easy => _easy(rnd),
    AlarmMathDifficulty.medium => _medium(rnd),
    AlarmMathDifficulty.hard => _hard(rnd),
  };
}

MathProblem _easy(Random rnd) {
  final a = rnd.nextInt(20) + 1;
  final b = rnd.nextInt(20) + 1;
  if (rnd.nextBool()) {
    return MathProblem('$a + $b', a + b);
  }
  final (x, y) = a >= b ? (a, b) : (b, a);
  return MathProblem('$x - $y', x - y);
}

MathProblem _medium(Random rnd) {
  switch (rnd.nextInt(3)) {
    case 0:
      final a = rnd.nextInt(90) + 10;
      final b = rnd.nextInt(90) + 10;
      return MathProblem('$a + $b', a + b);
    case 1:
      final a = rnd.nextInt(90) + 10;
      final b = rnd.nextInt(90) + 10;
      final (x, y) = a >= b ? (a, b) : (b, a);
      return MathProblem('$x - $y', x - y);
    default:
      // 小九九乘法或其逆运算
      final a = rnd.nextInt(11) + 2;
      final b = rnd.nextInt(8) + 2;
      if (rnd.nextBool()) {
        return MathProblem('$a × $b', a * b);
      }
      return MathProblem('${a * b} ÷ $b', a);
  }
}

MathProblem _hard(Random rnd) {
  switch (rnd.nextInt(3)) {
    case 0:
      final a = rnd.nextInt(900) + 100;
      final b = rnd.nextInt(900) + 100;
      return MathProblem('$a + $b', a + b);
    case 1:
      final a = rnd.nextInt(800) + 199;
      final b = rnd.nextInt(800) + 199;
      final (x, y) = a >= b ? (a, b) : (b, a);
      return MathProblem('$x - $y', x - y);
    default:
      // 两位乘一位或其逆运算
      final a = rnd.nextInt(90) + 10;
      final b = rnd.nextInt(12) + 3;
      if (rnd.nextBool()) {
        return MathProblem('$a × $b', a * b);
      }
      return MathProblem('${a * b} ÷ $b', a);
  }
}
