import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_client.dart';
import 'llm_types.dart';

/// OpenAI 兼容 `POST /chat/completions` 客户端。
///
/// 适用于 MiMo 平台及其它采用 OpenAI 接口约定的服务：
/// - 鉴权：`Authorization: Bearer <apiKey>`
/// - 工具：`tools: [{type: "function", function: {...}}]`
/// - 工具调用回传：`role: "assistant"` 带 `tool_calls`，`role: "tool"` 带结果
class OpenAiCompatClient implements LlmClient {
  OpenAiCompatClient({required this.config, http.Client? httpClient, this.timeout = const Duration(seconds: 90)})
      : _http = httpClient ?? http.Client();

  final LlmConfig config;
  final Duration timeout;
  final http.Client _http;

  @override
  Future<LlmResponse> complete({
    required List<ChatMessage> messages,
    List<ToolSpec> tools = const [],
  }) async {
    final body = <String, dynamic>{
      'model': config.model,
      'messages': messages.map(_messageToJson).toList(),
    };
    if (tools.isNotEmpty) {
      body['tools'] = tools.map((t) => t.toOpenAiJson()).toList();
      body['tool_choice'] = 'auto';
    }

    final http.Response res;
    try {
      res = await _http
          .post(config.chatCompletionsUri(), headers: config.headers, body: jsonEncode(body))
          .timeout(timeout);
    } on Exception catch (e) {
      throw LlmException('网络请求失败：$e');
    }

    if (res.statusCode != 200) {
      throw LlmException(_truncate(res.body), statusCode: res.statusCode);
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on Exception catch (e) {
      throw LlmException('响应不是合法 JSON：$e', statusCode: res.statusCode);
    }

    return _parseResponse(json);
  }

  /// 供应商消息 → OpenAI wire 形状。
  Map<String, dynamic> _messageToJson(ChatMessage m) {
    switch (m.role) {
      case ChatRole.system:
        return {'role': 'system', 'content': m.content};
      case ChatRole.user:
        return {'role': 'user', 'content': m.content};
      case ChatRole.assistant:
        final map = <String, dynamic>{
          'role': 'assistant',
          'content': m.content.isEmpty ? null : m.content,
        };
        if (m.toolCalls.isNotEmpty) {
          map['tool_calls'] = [
            for (final c in m.toolCalls)
              {
                'id': c.id,
                'type': 'function',
                'function': {
                  'name': c.name,
                  'arguments': jsonEncode(c.arguments),
                },
              }
          ];
        }
        return map;
      case ChatRole.tool:
        return {
          'role': 'tool',
          'tool_call_id': m.toolCallId,
          'content': m.content,
        };
    }
  }

  LlmResponse _parseResponse(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      throw const LlmException('响应缺少 choices');
    }
    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>? ?? {};
    final text = message['content'] as String? ?? '';
    final toolCallsJson = message['tool_calls'] as List<dynamic>? ?? [];

    final toolCalls = <ToolCall>[
      for (final raw in toolCallsJson)
        if (raw is Map<String, dynamic>) _toolCallFromJson(raw),
    ];

    return LlmResponse(
      text: text,
      toolCalls: toolCalls,
      finishReason: choice['finish_reason'] as String? ?? '',
    );
  }

  ToolCall _toolCallFromJson(Map<String, dynamic> json) {
    final fn = json['function'] as Map<String, dynamic>? ?? {};
    final argsRaw = fn['arguments'] as String? ?? '{}';
    Map<String, dynamic> args;
    try {
      final decoded = jsonDecode(argsRaw);
      args = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      args = <String, dynamic>{};
    }
    return ToolCall(
      id: json['id'] as String? ?? '',
      name: fn['name'] as String? ?? '',
      arguments: args,
    );
  }

  String _truncate(String s, [int max = 400]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
