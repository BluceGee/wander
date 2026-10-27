/// 与供应商无关的对话 / 工具调用数据结构。
///
/// 框架内部一律使用这里的类型，具体 API 形状（Anthropic Messages 等）
/// 由 [LlmClient] 的实现负责翻译。
library;

/// 对话消息角色。
enum ChatRole { system, user, assistant, tool }

/// 工具定义：名称、描述、JSON Schema 参数。
class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
    this.requiresConfirmation = false,
  });

  final String name;
  final String description;

  /// 参数的 JSON Schema（`type: object` + `properties` + `required`）。
  final Map<String, dynamic> parameters;

  /// 写操作建议置 true，UI 层可据此做二次确认。
  final bool requiresConfirmation;

  /// Anthropic Messages 的工具形状。
  Map<String, dynamic> toAnthropicJson() => {
        'name': name,
        'description': description,
        'input_schema': parameters,
      };
}

/// 模型发起的一次工具调用。
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// 供应商侧的调用 id，回传 tool_result 时要原样带上。
  final String id;
  final String name;

  /// 已解析为 Map 的工具参数（保证是 object；解析失败为空 Map）。
  final Map<String, dynamic> arguments;
}

/// 工具执行结果，作为 tool 消息回传给模型。
class ToolResult {
  const ToolResult({
    required this.toolCallId,
    required this.content,
    this.isError = false,
  });

  final String toolCallId;

  /// 结果内容（约定为 JSON 字符串，便于模型读取结构化数据）。
  final String content;
  final bool isError;
}

/// 一条对话消息。
class ChatMessage {
  const ChatMessage({
    required this.role,
    this.content = '',
    this.toolCalls = const [],
    this.toolCallId,
    this.isError = false,
  });

  final ChatRole role;

  /// 文本内容；assistant 消息带 toolCalls 时可为空。
  final String content;

  /// 仅 assistant 消息：模型要求执行的工具调用。
  final List<ToolCall> toolCalls;

  /// 仅 tool 消息：对应的工具调用 id。
  final String? toolCallId;

  /// 仅 tool 消息：是否为错误结果。
  final bool isError;

  factory ChatMessage.system(String content) =>
      ChatMessage(role: ChatRole.system, content: content);

  factory ChatMessage.user(String content) =>
      ChatMessage(role: ChatRole.user, content: content);

  factory ChatMessage.assistant({String content = '', List<ToolCall> toolCalls = const []}) =>
      ChatMessage(role: ChatRole.assistant, content: content, toolCalls: toolCalls);

  factory ChatMessage.tool({required ToolResult result}) => ChatMessage(
        role: ChatRole.tool,
        content: result.content,
        toolCallId: result.toolCallId,
        isError: result.isError,
      );
}

/// 一次模型调用的完整响应。
class LlmResponse {
  const LlmResponse({
    this.text = '',
    this.toolCalls = const [],
    this.finishReason = '',
  });

  /// 模型的文本回复（可能为空——只发工具调用时）。
  final String text;

  /// 模型要求执行的工具调用（可能为空）。
  final List<ToolCall> toolCalls;

  /// 原始 finish_reason（`stop` / `tool_calls` / `length` …）。
  final String finishReason;

  bool get wantsTools => toolCalls.isNotEmpty;
}

/// LLM 调用失败。[statusCode] 为 null 表示网络层错误。
class LlmException implements Exception {
  const LlmException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'LlmException(${statusCode == null ? 'network' : 'HTTP $statusCode'}: $message)';
}
