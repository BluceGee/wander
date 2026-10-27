import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xnl/core/models/account.dart';
import 'package:xnl/core/network/api_client.dart';
import 'package:xnl/core/storage/app_store.dart';
import 'package:xnl/core/storage/key_vault.dart';
import 'package:xnl/features/auth/login_page.dart';
import 'package:flutter/material.dart';

Future<AppStore> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return AppStore.create(prefs, vault: InMemoryKeyVault());
}

void main() {
  group('会话状态', () {
    test('首启未登录，welcomeDone 为 false', () async {
      final store = await freshStore();
      expect(store.isLoggedIn, isFalse);
      expect(store.welcomeDone, isFalse);
    });

    test('completeWelcome 后不再显示引导', () async {
      final store = await freshStore();
      await store.completeWelcome();
      expect(store.welcomeDone, isTrue);
    });

    test('saveSession 令牌进 KeyVault 不落明文 prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final vault = InMemoryKeyVault();
      final store = await AppStore.create(prefs, vault: vault);

      await store.saveSession(
        token: 'tok-abc',
        username: 'alice',
        createdAt: '2026-10-27T00:00:00Z',
      );

      expect(store.isLoggedIn, isTrue);
      expect(store.authUsername, 'alice');
      expect(vault.data['auth_token'], 'tok-abc');
      expect(prefs.getKeys(), isNot(contains('auth_token')));
    });

    test('clearSession 清空本地会话', () async {
      final store = await freshStore();
      await store.saveSession(token: 't', username: 'bob', createdAt: '');
      await store.clearSession();
      expect(store.isLoggedIn, isFalse);
      expect(store.authUsername, isEmpty);
    });
  });

  group('ApiClient', () {
    test('登录成功解析会话', () async {
      final client = ApiClient(
        baseUrl: 'https://srv.test',
        httpClient: MockClient((_) async => http.Response(
              '{"token":"t1","user":{"username":"alice","created_at":"2026-10-27"}}',
              200,
              headers: {'content-type': 'application/json'},
            )),
      );
      final session = await client.login('alice', 'password123');
      expect(session.token, 't1');
      expect(session.user.username, 'alice');
    });

    test('服务端错误文案透传', () async {
      final client = ApiClient(
        baseUrl: 'https://srv.test',
        httpClient: MockClient(
            (_) async => http.Response(
                  '{"detail":"用户名或密码错误"}',
                  401,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                )),
      );
      expect(
        () => client.login('alice', 'bad-pass'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '用户名或密码错误')
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('网络异常映射为可读文案', () async {
      final client = ApiClient(
        baseUrl: 'https://srv.test',
        httpClient: MockClient((_) async => throw const SocketException('x')),
      );
      expect(
        () => client.login('alice', 'password123'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('无法连接'))),
      );
    });
  });

  group('登录页', () {
    testWidgets('密码太短本地拦截，不发请求', (tester) async {
      var called = false;
      final fake = _FakeApi(onCall: () => called = true);
      final store = await freshStore();
      await tester.pumpWidget(MaterialApp(
          home: LoginPage(store: store, apiClient: fake)));

      await tester.enterText(find.byType(TextField).first, 'alice');
      await tester.enterText(find.byType(TextField).last, 'short');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(find.text('密码至少 8 位'), findsOneWidget);
      expect(called, isFalse);
    });

    testWidgets('登录成功后进入会话状态', (tester) async {
      final fake = _FakeApi(
        onCall: () {},
        session: const AuthSession(
          token: 'tok-1',
          user: UserProfile(username: 'alice', createdAt: '2026-10-27'),
        ),
      );
      final store = await freshStore();
      await tester.pumpWidget(MaterialApp(
          home: LoginPage(store: store, apiClient: fake)));

      await tester.enterText(find.byType(TextField).first, 'alice');
      await tester.enterText(find.byType(TextField).last, 'password123');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(store.isLoggedIn, isTrue);
      expect(store.authUsername, 'alice');
      expect(store.welcomeDone, isTrue);
    });

    testWidgets('跳过登录直接进 APP', (tester) async {
      final store = await freshStore();
      await tester.pumpWidget(MaterialApp(
          home: LoginPage(store: store, apiClient: _FakeApi(onCall: () {}))));

      expect(find.text('暂不登录，先逛逛'), findsOneWidget);
      await tester.tap(find.text('暂不登录，先逛逛'));
      await tester.pumpAndSettle();

      expect(store.welcomeDone, isTrue);
      expect(store.isLoggedIn, isFalse);
    });
  });
}

class _FakeApi extends ApiClient {
  _FakeApi({required this.onCall, this.session})
      : super(
          baseUrl: 'https://srv.test',
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        );

  final VoidCallback onCall;
  final AuthSession? session;

  @override
  Future<AuthSession> login(String username, String password) async {
    onCall();
    return session ??
        const AuthSession(
          token: 'tok',
          user: UserProfile(username: 'alice', createdAt: ''),
        );
  }

  @override
  Future<AuthSession> register(String username, String password) =>
      login(username, password);
}
