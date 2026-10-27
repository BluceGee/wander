import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xnl/features/alarm/alarm_permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// 模拟权限通道：按 permission 值返回状态码（1=granted 4=permanentlyDenied）。
  void mockPermissionChannel(int Function(int permission) statusOf) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'requestPermissions':
          final args = (call.arguments as List).cast<int>();
          return {for (final p in args) p: statusOf(p)};
        case 'checkPermissionStatus':
          return statusOf(call.arguments as int);
        case 'shouldShowRequestPermissionRationale':
          return false;
        case 'openAppSettings':
          return true;
      }
      return null;
    });
  }

  Widget harness() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AlarmPermissions.ensure(context),
              child: const Text('go'),
            ),
          ),
        ),
      );

  testWidgets('权限全部放行时不弹任何对话框', (tester) async {
    mockPermissionChannel((_) => 1);
    await tester.pumpWidget(harness());

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('精确闹钟被永久拒绝时引导去设置', (tester) async {
    mockPermissionChannel((p) =>
        p == Permission.scheduleExactAlarm.value ? 4 : 1);
    await tester.pumpWidget(harness());

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('需要「闹钟和提醒」权限'), findsOneWidget);
    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('国产 ROM 后台引导只弹一次', (tester) async {
    Widget guideHost() => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    AlarmPermissions.showVendorGuideOnce(context),
                child: const Text('go'),
              ),
            ),
          ),
        );
    await tester.pumpWidget(guideHost());

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('让闹钟准点响的小提示'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('让闹钟准点响的小提示'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kAlarmVendorGuideKey), isTrue);
  });

  testWidgets('权限通道不可用时 ensure 静默返回', (tester) async {
    // 不 mock 通道（MissingPluginException），也不应抛出
    await tester.pumpWidget(harness());
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
