import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xnl/core/agent/agent_service.dart';
import 'package:xnl/core/agent/agent_tool.dart';
import 'package:xnl/core/agent/llm_client.dart';
import 'package:xnl/core/agent/llm_types.dart';
import 'package:xnl/core/agent/openai_compat_client.dart';
import 'package:xnl/core/storage/app_store.dart';
import 'package:xnl/features/assistant/app_tools.dart';

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
  }) async {
    requestHistories.add([...messages]);
    return responses[_call++];
  }
}

Future<AppStore> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return AppStore(prefs);
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
        registry: ToolRegistry(buildAppTools(store)),
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
        registry: ToolRegistry(buildAppTools(store)),
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
        registry: ToolRegistry(buildAppTools(store)),
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
        registry: ToolRegistry(buildAppTools(store)),
        systemPrompt: 'sys',
        maxRounds: 2,
      );
      final history = <ChatMessage>[ChatMessage.user('循环')];
      final result = await service.run(history: history);

      expect(result, contains('上限'));
      expect(llm.requestHistories, hasLength(3)); // 2 轮 + 收尾那轮被上限挡掉前的调用
    });
  });

  group('OpenAiCompatClient', () {
    test('解析 tool_calls 并按 OpenAI 形状发请求', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'tool_calls',
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'call_9',
                      'type': 'function',
                      'function': {
                        'name': 'list_memos',
                        'arguments': '{"query":"买菜"}',
                      },
                    }
                  ],
                },
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = OpenAiCompatClient(
        config: const LlmConfig(
          baseUrl: 'https://mimo.example.com/v1/',
          apiKey: 'sk-test',
          model: 'mimo-v2.6-pro',
        ),
        httpClient: mockClient,
      );

      final response = await client.complete(
        messages: [ChatMessage.user('找一下买菜的备忘录')],
        tools: [for (final t in buildAppTools(await freshStore())) t.spec],
      );

      expect(captured.url.toString(), 'https://mimo.example.com/v1/chat/completions');
      expect(captured.headers['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body['model'], 'mimo-v2.6-pro');
      expect(body['tools'], isA<List<dynamic>>());
      expect(body['messages'], hasLength(1));

      expect(response.toolCalls.single.name, 'list_memos');
      expect(response.toolCalls.single.arguments['query'], '买菜');
    });

    test('非 200 抛 LlmException 且带状态码', () async {
      final mockClient =
          MockClient((_) async => http.Response('rate limited', 429));
      final client = OpenAiCompatClient(
        config: const LlmConfig(
            baseUrl: 'https://x.test/v1', apiKey: 'k', model: 'm'),
        httpClient: mockClient,
      );
      expect(
        () => client.complete(messages: [ChatMessage.user('hi')]),
        throwsA(isA<LlmException>()
            .having((e) => e.statusCode, 'statusCode', 429)),
      );
    });
  });

  group('工具校验', () {
    test('分类非法时报错并提示可选值', () async {
      final store = await freshStore();
      final registry = ToolRegistry(buildAppTools(store));
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
  });
}
