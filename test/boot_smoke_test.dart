import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xnl/app.dart';
import 'package:xnl/core/alarm/alarm_service.dart';
import 'package:xnl/core/storage/app_store.dart';
import 'package:xnl/core/storage/key_vault.dart';

import 'fakes.dart';

/// 启动冒烟：真机白屏问题的回归防护——
/// 首帧组合覆盖 深/浅色 × 已配/未配 Key × 登录/未登录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppStore store;
  late AlarmService alarms;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = await AppStore.create(prefs, vault: InMemoryKeyVault());
    alarms = buildFakeAlarmService(store).service;
    await store.completeWelcome();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(XnlApp(store: store, alarms: alarms));
    await tester.pumpAndSettle();
  }

  testWidgets('浅色 + 未配置 Key', (tester) async {
    await pumpApp(tester);
    expect(find.text('你好，我是 XNL 助手'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色 + 已配置 Key + 已登录', (tester) async {
    await store.setThemeMode(ThemeMode.dark);
    await store.setLlmApiKey('sk-test');
    await store.saveSession(
        token: 't', username: '小明', createdAt: '2026-10-28');
    await pumpApp(tester);
    expect(find.text('你好，小明'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色 + 输入栏/语音按钮可组合', (tester) async {
    await store.setThemeMode(ThemeMode.dark);
    await store.setLlmApiKey('sk-test');
    await pumpApp(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
