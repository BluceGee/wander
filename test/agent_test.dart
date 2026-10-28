import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xnl/core/agent/agent_service.dart';
import 'package:xnl/core/agent/agent_tool.dart';
import 'package:xnl/core/agent/llm_client.dart';
import 'package:xnl/core/agent/llm_types.dart';
import 'package:xnl/core/agent/anthropic_messages_client.dart';
import 'package:xnl/core/storage/app_store.dart';
import 'package:xnl/core/storage/key_vault.dart';
import 'package:xnl/core/utils/date_hint.dart';
import 'package:xnl/features/assistant/app_tools.dart';

import 'fakes.dart';

/// 按脚本回放的假 LLM：第 N 次调用返回第 N 个响应。
class FakeLlm implements LlmClient {
  FakeLlm(this.responses);

  final List<LlmResponse> responses;
  final List<List<ChatMessage>> requestHistories = [];
  int _call = 0;

  @override
  Future<LlmResponse> complete({
    required List<ChatMessage> messages,
    List<ToolSpec> tools = const [],
    void Function(String textDelta)? onText,
  }) async {
    requestHistories.add([...messages]);
    final response = responses[_call++];
    if (onText != null && response.text.isNotEmpty) {
      onText(response.text);
    }
    return response;
  }
}

Future<AppStore> freshStore(
    [Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return AppStore.create(prefs, vault: InMemoryKeyVault());
}

void main() {
  group('AgentService 工具循环', () {
    test('模型发起工具调用→执行→回传→最终文本', () async {
      final store = await freshStore();
      final llm = FakeLlm([
        LlmResponse(
          toolCalls: [
            ToolCall(
              id: 'call_1',
              name: 'add_expense',
              arguments: {
                'amount': 25,
                'is_expense': true,
                'category': '餐饮',
                'note': '午饭',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        const LlmResponse(text: '已记账：午饭 25 元。', finishReason: 'stop'),
      ]);

      final service = AgentService(
        llm: llm,
        registry: ToolRegistry(buildAppTools(store, buildFakeAlarmService(store).service)),
        systemPrompt: '你是测试助手',
      );

      final history = <ChatMessage>[ChatMessage.user('记一笔午饭25元')];
      final result = await service.run(history: history);

      expect(result, '已记账：午饭 25 元。');
      expect(store.expenses, hasLength(1));
      expect(store.expenses.single.amount, 25);
      expect(store.expenses.single.category, '餐饮');

      // 历史形状：user → assistant(tool_calls) → tool → assistant(text)
      expect(history.map((m) => m.role).toList(), [
        ChatRole.user,
        ChatRole.assistant,
        ChatRole.tool,
        ChatRole.assistant,
      ]);
      expect(history[1].toolCalls.single.id, 'call_1');
      expect(history[2].toolCallId, 'call_1');

      // 第二次请求要带上工具结果
      final secondRequest = llm.requestHistories[1];
      expect(secondRequest.first.role, ChatRole.system);
      expect(secondRequest.last.role, ChatRole.tool);
      expect(secondRequest.last.content, contains('ok'));
    });

    test('工具执行失败回传 is_error，不中断循环', () async {
      final store = await freshStore();
      final llm = FakeLlm([
        LlmResponse(
          toolCalls: [
            ToolCall(id: 'c1', name: 'add_expense', arguments: {
              'amount': -5,
              'category': '餐饮',
            }),
          ],
          finishReason: 'tool_calls',
        ),
        const LlmResponse(text: '金额不对，请重试', finishReason: 'stop'),
      ]);

      final service = AgentService(
        llm: llm,
        registry: ToolRegistry(buildAppTools(store, buildFakeAlarmService(store).service)),
        systemPrompt: 'sys',
      );
      final history = <ChatMessage>[ChatMessage.user('记一笔')];
      await service.run(history: history);

      expect(store.expenses, isEmpty);
      expect(history[2].isError, isTrue);
      expect(history[2].content, contains('error'));
    });

    test('写操作被用户拒绝时不执行并回传 is_error', () async {
      final store = await freshStore();
      final llm = FakeLlm([
        LlmResponse(
          toolCalls: [
            ToolCall(id: 'c1', name: 'create_memo', arguments: {
              'title': '不该被创建',
              'content': 'x',
            }),
          ],
          finishReason: 'tool_calls',
        ),
        const LlmResponse(text: '好的，不创建了。', finishReason: 'stop'),
      ]);

      final service = AgentService(
        llm: llm,
        registry: ToolRegistry(buildAppTools(store, buildFakeAlarmService(store).service)),
        systemPrompt: 'sys',
        approveTool: (call) async => call.name != 'create_memo',
      );
      final history = <ChatMessage>[ChatMessage.user('写个备忘录')];
      await service.run(history: history);

      expect(store.memos, isEmpty);
      expect(history[2].isError, isTrue);
      expect(history[2].content, contains('拒绝'));
    });

    test('超过 maxRounds 时停止', () async {
      final store = await freshStore();
      // 模型每次都要求调工具
      LlmResponse alwaysTool(_) => LlmResponse(
            toolCalls: [
              ToolCall(id: 'c', name: 'get_month_summary', arguments: const {}),
            ],
            finishReason: 'tool_calls',
          );

      final llm = FakeLlm(List.generate(10, alwaysTool));
      final service = AgentService(
        llm: llm,
        registry: ToolRegistry(buildAppTools(store, buildFakeAlarmService(store).service)),
        systemPrompt: 'sys',
        maxRounds: 2,
      );
      final history = <ChatMessage>[ChatMessage.user('循环')];
      final result = await service.run(history: history);

      expect(result, contains('上限'));
      expect(llm.requestHistories, hasLength(3)); // 2 轮 + 收尾那轮被上限挡掉前的调用
    });
  });

  group('AnthropicMessagesClient', () {
    test('按 Messages 形状发请求并解析 tool_use', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_9',
                'name': 'list_memos',
                'input': {'query': '买菜'},
              },
            ],
            'stop_reason': 'tool_use',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = AnthropicMessagesClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: mockClient,
      );

      final specStore = await freshStore();
      final allTools = buildAppTools(
          specStore, buildFakeAlarmService(specStore).service);
      final response = await client.complete(
        messages: [ChatMessage.user('找一下买菜的备忘录')],
        tools: [for (final t in allTools) t.spec],
      );

      expect(captured.url.toString(), '$kLlmBaseUrl/messages');
      expect(captured.headers['x-api-key'], 'sk-test');
      expect(captured.headers['anthropic-version'], '2023-06-01');
      final body = jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body['model'], kLlmModel);
      expect(body['max_tokens'], isA<int>());
      final tool = (body['tools'] as List).first as Map<String, dynamic>;
      expect(tool['input_schema'], isA<Map<String, dynamic>>());
      expect(body['messages'], hasLength(1));

      expect(response.toolCalls.single.name, 'list_memos');
      expect(response.toolCalls.single.arguments['query'], '买菜');
      expect(response.finishReason, 'tool_use');
    });

    test('system 顶层下发，tool 结果合并成一条 user 消息', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': '好的'},
            ],
            'stop_reason': 'end_turn',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = AnthropicMessagesClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: mockClient,
      );

      await client.complete(messages: [
        ChatMessage.system('系统提示'),
        ChatMessage.user('查账'),
        ChatMessage.assistant(toolCalls: [
          ToolCall(id: 'a', name: 'list_memos', arguments: const {}),
          ToolCall(id: 'b', name: 'list_alarms', arguments: const {}),
        ]),
        ChatMessage.tool(
            result: ToolResult(toolCallId: 'a', content: '{"ok":true}')),
        ChatMessage.tool(
            result: ToolResult(
                toolCallId: 'b', content: '{"ok":false}', isError: true)),
      ]);

      final body = jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body['system'], '系统提示');
      // user → assistant(tool_use×2) → user(tool_result×2)
      expect(body['messages'], hasLength(3));
      expect(body['messages'][0]['role'], 'user');
      expect(body['messages'][1]['role'], 'assistant');
      final assistantBlocks = body['messages'][1]['content'] as List;
      expect(assistantBlocks.map((b) => b['type']), ['tool_use', 'tool_use']);
      expect(assistantBlocks[1]['input'], isA<Map<String, dynamic>>());
      final toolBlocks = body['messages'][2]['content'] as List;
      expect(toolBlocks, hasLength(2));
      expect(toolBlocks[0]['type'], 'tool_result');
      expect(toolBlocks[0]['tool_use_id'], 'a');
      expect(toolBlocks[1]['is_error'], isTrue);
    });

    test('非 200 抛 LlmException 且带状态码', () async {
      final mockClient =
          MockClient((_) async => http.Response('rate limited', 429));
      final client = AnthropicMessagesClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: mockClient,
      );
      expect(
        () => client.complete(messages: [ChatMessage.user('hi')]),
        throwsA(isA<LlmException>()
            .having((e) => e.statusCode, 'statusCode', 429)),
      );
    });

    test('流式：SSE 文本增量实时回调，tool_use 参数分片拼装', () async {
      final sse = [
        'event: message_start',
        'data: {"type":"message_start","message":{"id":"msg_1"}}',
        '',
        'event: content_block_start',
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}',
        '',
        'event: content_block_delta',
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"内部思考"}}',
        '',
        'event: content_block_stop',
        'data: {"type":"content_block_stop","index":0}',
        '',
        'event: content_block_start',
        'data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}',
        '',
        'event: content_block_delta',
        'data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"你好"}}',
        '',
        'event: content_block_delta',
        'data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"！"}}',
        '',
        'event: content_block_stop',
        'data: {"type":"content_block_stop","index":1}',
        '',
        'event: content_block_start',
        'data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"call_7","name":"list_memos","input":{}}}',
        '',
        'event: content_block_delta',
        'data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\": "}}',
        '',
        'event: content_block_delta',
        'data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\\"买菜\\"}"}}',
        '',
        'event: content_block_stop',
        'data: {"type":"content_block_stop","index":2}',
        '',
        'event: message_delta',
        'data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}',
        '',
        'event: message_stop',
        'data: {"type":"message_stop"}',
        '',
      ].join('\n');

      final mockClient = MockClient((request) async {
        final body =
            jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;
        expect(body['stream'], isTrue); // 走流式分支才带 stream
        return http.Response.bytes(
          utf8.encode(sse),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final deltas = <String>[];
      final client = AnthropicMessagesClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: mockClient,
      );
      final response = await client.complete(
        messages: [ChatMessage.user('查一下买菜的备忘录')],
        onText: deltas.add,
      );

      expect(deltas, ['你好', '！']);
      expect(response.text, '你好！');
      expect(response.toolCalls.single.name, 'list_memos');
      expect(response.toolCalls.single.arguments['query'], '买菜');
      expect(response.finishReason, 'tool_use');
    });
  });

  group('工具校验', () {
    test('分类非法时报错并提示可选值', () async {
      final store = await freshStore();
      final registry = ToolRegistry(buildAppTools(store, buildFakeAlarmService(store).service));
      final result = await registry.run(ToolCall(
        id: 'c1',
        name: 'add_expense',
        arguments: {'amount': 10, 'category': '外星人'},
      ));
      expect(result.isError, isTrue);
      expect(result.content, contains('无效'));
    });

    test('未知工具名回传错误', () async {
      final registry = ToolRegistry([]);
      final result =
          await registry.run(ToolCall(id: 'c1', name: 'nope', arguments: {}));
      expect(result.isError, isTrue);
    });

    test('口语日期被归一并回显，识别不了时报错含示例', () async {
      final store = await freshStore();
      final registry = ToolRegistry(buildAppTools(store, buildFakeAlarmService(store).service));
      final ok = await registry.run(ToolCall(
        id: 'c1',
        name: 'add_expense',
        arguments: {'amount': 10, 'category': '餐饮', 'date': '昨天'},
      ));
      expect(ok.isError, isFalse);
      expect(ok.content, contains(DateFormat('yyyy-MM-dd')
          .format(DateTime.now().subtract(const Duration(days: 1)))));

      final bad = await registry.run(ToolCall(
        id: 'c2',
        name: 'add_expense',
        arguments: {'amount': 10, 'category': '餐饮', 'date': '上个礼拜的某天'},
      ));
      expect(bad.isError, isTrue);
      expect(bad.content, contains('无法识别'));
      expect(bad.content, contains('上周三'));
    });
  });

  group('口语日期解析', () {
    final now = DateTime(2026, 10, 26); // 周一

    test('今天/昨天/明天', () {
      expect(tryParseDateHint('今天', now: now), DateTime(2026, 10, 26));
      expect(tryParseDateHint('昨天', now: now), DateTime(2026, 10, 25));
      expect(tryParseDateHint('前天', now: now), DateTime(2026, 10, 24));
      expect(tryParseDateHint('明天', now: now), DateTime(2026, 10, 27));
    });

    test('N号：本月已过取本月，未到取上月', () {
      expect(tryParseDateHint('3号', now: now), DateTime(2026, 10, 3));
      expect(tryParseDateHint('28日', now: now), DateTime(2026, 9, 28));
    });

    test('周X：无前缀取最近已过，上周/本周按自然周', () {
      // 2026-10-26 是周一
      expect(tryParseDateHint('周三', now: now), DateTime(2026, 10, 21));
      expect(tryParseDateHint('周一', now: now), DateTime(2026, 10, 26));
      // 上周（10-19 ~ 10-25）的周三
      expect(tryParseDateHint('上周三', now: now), DateTime(2026, 10, 21));
      expect(tryParseDateHint('本周五', now: now), DateTime(2026, 10, 30));

      // 换到周三：「上周三」与「周三」应区分开
      final wednesday = DateTime(2026, 10, 28);
      expect(tryParseDateHint('周三', now: wednesday), DateTime(2026, 10, 28));
      expect(tryParseDateHint('上周三', now: wednesday), DateTime(2026, 10, 21));
    });

    test('M月D日 与 ISO 格式', () {
      expect(tryParseDateHint('10月1日', now: now), DateTime(2026, 10, 1));
      expect(tryParseDateHint('2026-10-1', now: now), DateTime(2026, 10, 1));
      // 今年还没到 → 去年
      expect(tryParseDateHint('12月1日', now: now), DateTime(2025, 12, 1));
    });

    test('非法日期不猜', () {
      expect(tryParseDateHint('2月30日', now: now), isNull);
      expect(tryParseDateHint('乱七八糟', now: now), isNull);
      expect(tryParseDateHint('', now: now), isNull);
    });
  });

  group('API Key 存储安全', () {
    test('保存后 Key 只进 KeyVault，不落 SharedPreferences 明文', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final vault = InMemoryKeyVault();
      final store = await AppStore.create(prefs, vault: vault);

      await store.setLlmApiKey('sk-secret');

      expect(vault.data['llm_api_key'], 'sk-secret');
      final keys = prefs.getKeys();
      expect(keys, isNot(contains('llmApiKey')));
      expect(
        keys.every((k) => (prefs.get(k)?.toString() ?? '').contains('sk-secret') == false),
        isTrue,
        reason: 'SharedPreferences 的任何键里都不应出现 API Key',
      );
    });

    test('旧版明文键自动迁入 KeyVault 并从 prefs 清除', () async {
      SharedPreferences.setMockInitialValues({
        'llmBaseUrl': 'https://mimo.example.com/v1',
        'llmApiKey': 'sk-legacy',
        'llmModel': 'mimo-v2.6-pro',
      });
      final prefs = await SharedPreferences.getInstance();
      final vault = InMemoryKeyVault();
      final store = await AppStore.create(prefs, vault: vault);

      expect(store.llmConfig.apiKey, 'sk-legacy');
      expect(vault.data['llm_api_key'], 'sk-legacy');
      expect(prefs.getKeys(), isNot(contains('llmApiKey')));
      // 端点/模型已写死进代码，残留配置键一并清掉
      expect(prefs.getKeys(), isNot(contains('llmBaseUrl')));
      expect(prefs.getKeys(), isNot(contains('llmModel')));
    });

    test('语音播报开关默认开并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store =
          await AppStore.create(prefs, vault: InMemoryKeyVault());

      expect(store.voiceReplyEnabled, isTrue);
      await store.setVoiceReplyEnabled(false);
      expect(store.voiceReplyEnabled, isFalse);
      expect(prefs.getBool('voiceReply'), isFalse);
    });
  });
}
