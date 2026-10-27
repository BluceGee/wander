import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xnl/app.dart';
import 'package:xnl/core/models/expense.dart';
import 'package:xnl/core/models/memo.dart';
import 'package:xnl/core/storage/app_store.dart';
import 'package:xnl/core/storage/key_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = await AppStore.create(prefs, vault: InMemoryKeyVault());
  });

  test('备忘录增删改查', () async {
    final memo = Memo.create(title: '购物清单', content: '牛奶、面包');
    await store.addMemo(memo);
    expect(store.memos, hasLength(1));

    await store.updateMemo(memo.copyWith(title: '周末采购'));
    expect(store.memos.single.title, '周末采购');

    await store.deleteMemo(memo.id);
    expect(store.memos, isEmpty);
  });

  test('账单汇总按分类合计', () async {
    await store.addExpense(ExpenseRecord.create(
        amount: 30, isExpense: true, category: '餐饮'));
    await store.addExpense(ExpenseRecord.create(
        amount: 20, isExpense: true, category: '餐饮'));
    await store.addExpense(ExpenseRecord.create(
        amount: 100, isExpense: false, category: '工资'));

    final summary = ExpenseSummary.of(store.expenses);
    expect(summary.totalExpense, 50);
    expect(summary.totalIncome, 100);
    expect(summary.balance, 50);
    expect(summary.byCategory['餐饮'], 50);
  });

  testWidgets('首启显示登录引导，可跳过进入对话主页', (tester) async {
    await tester.pumpWidget(XnlApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('XNL 工具箱'), findsOneWidget); // 登录页标题
    expect(find.text('暂不登录，先逛逛'), findsOneWidget);

    await tester.tap(find.text('暂不登录，先逛逛'));
    await tester.pumpAndSettle();

    // 豆包式对话主页：问候 + 快捷指令
    expect(find.text('你好，我是 XNL 助手'), findsOneWidget);
    expect(find.text('记一笔午饭 25 元'), findsOneWidget);
    expect(find.byIcon(Icons.widgets_outlined), findsOneWidget);
  });

  testWidgets('工具页展示功能入口', (tester) async {
    await tester.pumpWidget(XnlApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂不登录，先逛逛'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.widgets_outlined));
    await tester.pumpAndSettle();

    expect(find.text('全部功能'), findsWidgets);
    expect(find.text('本月支出'), findsOneWidget);
    expect(find.text('本月收入'), findsOneWidget);
    expect(find.text('备忘录'), findsWidgets);
    expect(find.text('记账'), findsWidgets);
    expect(find.text('小游戏'), findsWidgets);
    expect(find.text('随手记，随时查'), findsOneWidget);
  });

  testWidgets('从工具页新建备忘录后出现在列表中', (tester) async {
    await tester.pumpWidget(XnlApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂不登录，先逛逛'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.widgets_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.note_alt_outlined));
    await tester.pumpAndSettle();
    expect(find.text('还没有备忘录'), findsOneWidget);

    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '第一条');
    await tester.enterText(find.byType(TextField).last, '内容');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('第一条'), findsOneWidget);
    expect(find.textContaining('内容'), findsOneWidget);
  });

  testWidgets('welcomeDone 后直接进对话主页', (tester) async {
    await store.completeWelcome();
    await tester.pumpWidget(XnlApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('你好，我是 XNL 助手'), findsOneWidget);
  });
}
