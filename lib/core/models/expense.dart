import 'package:flutter/foundation.dart';

/// 支出 / 收入分类。
class ExpenseCategory {
  const ExpenseCategory(this.name, this.icon);

  final String name;
  final String icon;

  static const List<ExpenseCategory> expenseCategories = [
    ExpenseCategory('餐饮', '🍜'),
    ExpenseCategory('交通', '🚌'),
    ExpenseCategory('购物', '🛍️'),
    ExpenseCategory('娱乐', '🎮'),
    ExpenseCategory('居家', '🏠'),
    ExpenseCategory('医疗', '💊'),
    ExpenseCategory('教育', '📚'),
    ExpenseCategory('其他', '📦'),
  ];

  static const List<ExpenseCategory> incomeCategories = [
    ExpenseCategory('工资', '💼'),
    ExpenseCategory('奖金', '🏆'),
    ExpenseCategory('理财', '📈'),
    ExpenseCategory('红包', '🧧'),
    ExpenseCategory('其他', '📦'),
  ];

  /// 按分类名取图标，未知分类回退为 📦。
  static String iconOf(String name) {
    for (final c in [...expenseCategories, ...incomeCategories]) {
      if (c.name == name) return c.icon;
    }
    return '📦';
  }
}

/// 一条账单记录。
class ExpenseRecord {
  ExpenseRecord({
    required this.id,
    required this.amount,
    required this.isExpense,
    required this.category,
    required this.note,
    required this.date,
  });

  final String id;

  /// 金额（始终为正数，收入/支出由 [isExpense] 决定）。
  final double amount;
  final bool isExpense;
  final String category;
  final String note;
  final DateTime date;

  factory ExpenseRecord.create({
    required double amount,
    required bool isExpense,
    required String category,
    String note = '',
    DateTime? date,
  }) {
    final now = date ?? DateTime.now();
    return ExpenseRecord(
      id: '${now.microsecondsSinceEpoch}-$amount',
      amount: amount,
      isExpense: isExpense,
      category: category,
      note: note,
      date: now,
    );
  }

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) {
    return ExpenseRecord(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      isExpense: json['isExpense'] as bool? ?? true,
      category: json['category'] as String? ?? '其他',
      note: json['note'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'isExpense': isExpense,
        'category': category,
        'note': note,
        'date': date.toIso8601String(),
      };

  @override
  bool operator ==(Object other) => other is ExpenseRecord && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class ExpenseSummary {
  const ExpenseSummary({
    required this.totalExpense,
    required this.totalIncome,
    required this.byCategory,
  });

  final double totalExpense;
  final double totalIncome;

  /// 支出按分类汇总（分类名 -> 金额）。
  final Map<String, double> byCategory;

  double get balance => totalIncome - totalExpense;

  factory ExpenseSummary.of(List<ExpenseRecord> records) {
    double expense = 0;
    double income = 0;
    final byCategory = <String, double>{};
    for (final r in records) {
      if (r.isExpense) {
        expense += r.amount;
        byCategory[r.category] = (byCategory[r.category] ?? 0) + r.amount;
      } else {
        income += r.amount;
      }
    }
    return ExpenseSummary(
      totalExpense: expense,
      totalIncome: income,
      byCategory: byCategory,
    );
  }
}
