import 'dart:convert';

import 'agent_tool.dart';
import 'llm_client.dart';
import 'llm_types.dart';

/// 写操作确认回调：返回 true 执行，false 拒绝（会以 is_error 回传模型）。
typedef ToolApproval = Future<bool> Function(ToolCall call);

/// agent 循环：用户消息 → 模型 → （工具调用 → 执行 → 回传）* → 最终回复。
///
/// 与 UI 解耦：进度通过 [onMessage] 回调逐条吐出（含工具调用与结果），
/// 完整历史由调用方持有。[maxRounds] 防止工具循环失控。
class AgentService {
  AgentService({
    required this.llm,
    required this.registry,
    required this.systemPrompt,
    this.maxRounds = 8,
    this.approveTool,
  });

  final LlmClient llm;
  final ToolRegistry registry;
  final String systemPrompt;

  /// 一次提问最多允许的「模型→工具→模型」轮数。
  final int maxRounds;

  /// 对 [ToolSpec.requiresConfirmation] 的工具做用户确认；
  /// 不提供则默认放行（如无界面的测试/自动化场景）。
  final ToolApproval? approveTool;

  /// 执行一轮 agent 对话。
  ///
  /// [history] 为完整会话历史（会被就地追加）；每产生一条新消息
  /// 就回调 [onMessage] 一次。返回模型的最终文本回复。
  Future<String> run({
    required List<ChatMessage> history,
    void Function(ChatMessage message)? onMessage,
  }) async {
    var rounds = 0;

    while (true) {
      final response = await llm.complete(
        messages: [
          ChatMessage.system(systemPrompt),
          ...history,
        ],
        tools: registry.specs,
      );

      if (!response.wantsTools) {
        final finalMessage = ChatMessage.assistant(content: response.text);
        history.add(finalMessage);
        onMessage?.call(finalMessage);
        return response.text;
      }

      rounds++;
      if (rounds > maxRounds) {
        final notice = ChatMessage.assistant(
          content: '（工具调用轮数已达上限 $maxRounds，已停止。当前进展已保留，可以换种方式问我。）',
        );
        history.add(notice);
        onMessage?.call(notice);
        return notice.content;
      }

      final toolCallMessage = ChatMessage.assistant(toolCalls: response.toolCalls);
      history.add(toolCallMessage);
      onMessage?.call(toolCallMessage);

      // 一个 assistant 消息里的多个工具调用必须全部回传，
      // 且要放在同一批 tool 消息里。
      for (final call in response.toolCalls) {
        final result = await _runGuarded(call);
        final toolMessage = ChatMessage.tool(result: result);
        history.add(toolMessage);
        onMessage?.call(toolMessage);
      }
    }
  }

  Future<ToolResult> _runGuarded(ToolCall call) async {
    final spec = registry.find(call.name)?.spec;
    if (spec?.requiresConfirmation == true && approveTool != null) {
      final approved = await approveTool!(call);
      if (!approved) {
        return ToolResult(
          toolCallId: call.id,
          isError: true,
          content: jsonEncode({'error': '用户拒绝了此操作，不要重试。换个方式询问用户。'}),
        );
      }
    }
    return registry.run(call);
  }
}
