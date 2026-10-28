import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_client.dart';
import 'llm_types.dart';

/// Anthropic Messages API 客户端（`POST /v1/messages`）。
///
/// 适用于 Claude API 与任何 Anthropic 兼容端点：
/// - 鉴权：`x-api-key` + `anthropic-version` 头；
/// - 系统提示词：顶层 `system` 字段（不是消息角色）；
/// - 工具：`tools: [{name, description, input_schema}]`；
/// - 工具调用回传：assistant 的 `tool_use` 块 → user 的 `tool_result` 块，
///   同一批 tool_result 合并进同一条 user 消息（协议要求）；
/// - 响应：`content` 内容块数组 + `stop_reason`。
class AnthropicMessagesClient implements LlmClient {
  AnthropicMessagesClient({
    required this.config,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 120),
    this.maxTokens = 16000,
  }) : _http = httpClient ?? http.Client();

  final LlmConfig config;

  /// 单次请求超时（非流式，thinking 模型可能较慢）。
  final Duration timeout;

  /// max_tokens 为 Messages API 必填项。
  final int maxTokens;

  final http.Client _http;

  @override
  Future<LlmResponse> complete({
    required List<ChatMessage> messages,
    List<ToolSpec> tools = const [],
    void Function(String textDelta)? onText,
  }) async {
    final body = <String, dynamic>{
      'model': kLlmModel,
      'max_tokens': maxTokens,
      'messages': _messagesToJson(messages),
    };
    final system = _systemText(messages);
    if (system.isNotEmpty) body['system'] = system;
    if (tools.isNotEmpty) {
      body['tools'] = [for (final t in tools) t.toAnthropicJson()];
    }

    if (onText != null) {
      body['stream'] = true;
      return _completeStreaming(body, onText);
    }

    final http.Response res;
    try {
      res = await _http
          .post(
            config.messagesUri(),
            headers: config.headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on Exception catch (e) {
      throw LlmException('网络请求失败：$e');
    }

    if (res.statusCode != 200) {
      throw LlmException(_errorMessage(res.body), statusCode: res.statusCode);
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on Exception catch (e) {
      throw LlmException('响应不是合法 JSON：$e', statusCode: res.statusCode);
    }
    return _parseResponse(json);
  }

  /// 流式请求：`stream: true` + SSE，文本增量经 [onText] 实时回调。
  Future<LlmResponse> _completeStreaming(
    Map<String, dynamic> body,
    void Function(String textDelta) onText,
  ) async {
    final request = http.Request('POST', config.messagesUri())
      ..headers.addAll(config.headers)
      ..body = jsonEncode(body);

    final http.StreamedResponse res;
    try {
      res = await _http.send(request).timeout(timeout);
    } on Exception catch (e) {
      throw LlmException('网络请求失败：$e');
    }

    if (res.statusCode != 200) {
      final raw = await res.stream.bytesToString();
      throw LlmException(_errorMessage(raw), statusCode: res.statusCode);
    }

    final textsByIndex = <int, StringBuffer>{};
    final toolsByIndex = <int, _PendingTool>{};
    var stopReason = '';
    final dataBuf = StringBuffer();

    void dispatchEvent() {
      if (dataBuf.isEmpty) return;
      final raw = dataBuf.toString();
      dataBuf.clear();
      final Map<String, dynamic> event;
      try {
        event = jsonDecode(raw) as Map<String, dynamic>;
      } on FormatException {
        return; // 非 JSON 的事件行直接忽略
      }
      switch (event['type']) {
        case 'content_block_start':
          final index = event['index'] as int? ?? 0;
          final block = event['content_block'] as Map<String, dynamic>? ?? const {};
          if (block['type'] == 'tool_use') {
            toolsByIndex[index] = _PendingTool(
              id: block['id'] as String? ?? '',
              name: block['name'] as String? ?? '',
            );
          }
        case 'content_block_delta':
          final index = event['index'] as int? ?? 0;
          final delta = event['delta'] as Map<String, dynamic>? ?? const {};
          switch (delta['type']) {
            case 'text_delta':
              final text = delta['text'] as String? ?? '';
              if (text.isEmpty) return;
              (textsByIndex[index] ??= StringBuffer()).write(text);
              onText(text);
            case 'input_json_delta':
              toolsByIndex[index]
                  ?.partialJson
                  .write(delta['partial_json'] as String? ?? '');
            default:
              // thinking_delta / signature_delta 等一律忽略
              break;
          }
        case 'content_block_stop':
          final index = event['index'] as int? ?? 0;
          toolsByIndex[index]?.finish();
        case 'message_delta':
          final delta = event['delta'] as Map<String, dynamic>? ?? const {};
          stopReason = delta['stop_reason'] as String? ?? stopReason;
        case 'error':
          final err = event['error'] as Map<String, dynamic>?;
          throw LlmException(err?['message'] as String? ?? '流式响应出错');
        default:
          break;
      }
    }

    // SSE 块可能在任意字节处断开，逐行缓冲再派发
    final lineBuf = StringBuffer();
    try {
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        lineBuf.write(chunk);
        var text = lineBuf.toString();
        while (true) {
          final nl = text.indexOf('\n');
          if (nl < 0) break;
          final line = text.substring(0, nl).trimRight();
          text = text.substring(nl + 1);
          if (line.isEmpty) {
            dispatchEvent();
          } else if (line.startsWith('data:')) {
            dataBuf.write(line.substring(5).trimLeft());
          }
          // event:/id: 行忽略（事件类型在 JSON 里）
        }
        lineBuf
          ..clear()
          ..write(text);
      }
      dispatchEvent(); // 流正常结束
    } on Exception catch (e) {
      throw LlmException('流式读取中断：$e');
    }

    final text = textsByIndex.values.map((b) => b.toString()).join();
    var outText = text;
    if (outText.isEmpty && stopReason == 'refusal') {
      outText = '（模型拒绝了这次请求，换个问法试试）';
    }
    return LlmResponse(
      text: outText,
      toolCalls: [for (final t in toolsByIndex.values) t.build()],
      finishReason: stopReason,
    );
  }

  // ---------- 请求侧 ----------

  /// system 消息汇总为顶层 `system` 字段（Messages API 不允许 system 角色消息）。
  String _systemText(List<ChatMessage> messages) => [
        for (final m in messages)
          if (m.role == ChatRole.system) m.content,
      ].join('\n\n');

  /// 框架消息 → Messages API 的 `messages` 数组。
  ///
  /// - user/assistant 连续消息合并，保证 user/assistant 交替；
  /// - 连续 tool 消息合并为同一条 user 消息的多个 tool_result 块
  ///   （拆开发会诱导模型不再并行调用工具）。
  List<Map<String, dynamic>> _messagesToJson(List<ChatMessage> messages) {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      switch (m.role) {
        case ChatRole.system:
          break; // 顶层 system 字段处理
        case ChatRole.user:
          _appendUserBlock(out, {'type': 'text', 'text': m.content});
        case ChatRole.assistant:
          final blocks = <Map<String, dynamic>>[
            if (m.content.isNotEmpty) {'type': 'text', 'text': m.content},
            for (final c in m.toolCalls)
              {
                'type': 'tool_use',
                'id': c.id,
                'name': c.name,
                'input': c.arguments,
              },
          ];
          if (blocks.isEmpty) {
            blocks.add({'type': 'text', 'text': ''});
          }
          final last = out.isEmpty ? null : out.last;
          if (last != null && last['role'] == 'assistant') {
            (last['content'] as List<Map<String, dynamic>>).addAll(blocks);
          } else {
            out.add({'role': 'assistant', 'content': blocks});
          }
        case ChatRole.tool:
          _appendUserBlock(out, {
            'type': 'tool_result',
            'tool_use_id': m.toolCallId,
            'content': m.content,
            'is_error': m.isError,
          });
      }
    }
    return out;
  }

  /// 追加一个 user 侧内容块；上一条已是 user 时并入同一条消息。
  void _appendUserBlock(List<Map<String, dynamic>> out, Map<String, dynamic> block) {
    final last = out.isEmpty ? null : out.last;
    if (last != null && last['role'] == 'user') {
      (last['content'] as List<Map<String, dynamic>>).add(block);
    } else {
      out.add({
        'role': 'user',
        'content': <Map<String, dynamic>>[block],
      });
    }
  }

  // ---------- 响应侧 ----------

  LlmResponse _parseResponse(Map<String, dynamic> json) {
    final content = json['content'] as List<dynamic>? ?? const [];
    final texts = <String>[];
    final toolCalls = <ToolCall>[];
    for (final raw in content) {
      if (raw is! Map<String, dynamic>) continue;
      switch (raw['type']) {
        case 'text':
          texts.add(raw['text'] as String? ?? '');
        case 'tool_use':
          toolCalls.add(ToolCall(
            id: raw['id'] as String? ?? '',
            name: raw['name'] as String? ?? '',
            arguments: (raw['input'] as Map<String, dynamic>?) ?? const {},
          ));
        default:
          // thinking / redacted_thinking 等一律忽略，也不回传历史
          break;
      }
    }

    final stopReason = json['stop_reason'] as String? ?? '';
    var text = texts.join();
    if (text.isEmpty && stopReason == 'refusal') {
      text = '（模型拒绝了这次请求，换个问法试试）';
    }
    return LlmResponse(text: text, toolCalls: toolCalls, finishReason: stopReason);
  }

  /// 解析 Anthropic 错误体 `{"type":"error","error":{"message":...}}`，
  /// 取不到则截断原文。
  String _errorMessage(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final err = json['error'];
        if (err is Map<String, dynamic> && err['message'] is String) {
          return err['message'] as String;
        }
      }
    } on FormatException {
      // 非 JSON 错误体，走截断
    }
    return body.length <= 400 ? body : '${body.substring(0, 400)}…';
  }
}

/// 流式响应里正在累积的 tool_use 块（`input_json_delta` 分片拼参数）。
class _PendingTool {
  _PendingTool({required this.id, required this.name});

  final String id;
  final String name;
  final StringBuffer partialJson = StringBuffer();
  Map<String, dynamic>? _input;

  /// 参数 JSON 拼完（content_block_stop）后解析；失败按空参处理。
  void finish() {
    final raw = partialJson.toString().trim();
    if (raw.isEmpty) {
      _input = const {};
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      _input = decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      _input = const {};
    }
  }

  ToolCall build() => ToolCall(
        id: id,
        name: name,
        arguments: _input ??
            const {}, // stop 事件丢失时退化为空参
      );
}
