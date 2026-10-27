import 'llm_types.dart';

/// MiMo Anthropic 兼容端点（写死，非配置项）。
const kLlmBaseUrl = 'https://token-plan-cn.xiaomimimo.com/anthropic/v1';

/// 对话语言模型（写死，非配置项）。
const kLlmModel = 'mimo-v2.6-flash';

/// LLM 接入配置：只有 API Key 是用户手动填的。
///
/// 端点与模型写死在 [kLlmBaseUrl] / [kLlmModel]（MiMo，Anthropic Messages 协议）。
class LlmConfig {
  const LlmConfig({required this.apiKey});

  final String apiKey;

  /// Messages API 协议版本头。
  static const anthropicVersion = '2023-06-01';

  bool get isConfigured => apiKey.trim().isNotEmpty;

  /// Messages 端点：`…/v1/messages`。
  Uri messagesUri() => Uri.parse('$kLlmBaseUrl/messages');

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'x-api-key': apiKey.trim(),
        'anthropic-version': anthropicVersion,
      };

  static const empty = LlmConfig(apiKey: '');
}

/// 供应商适配层接口：把框架内的消息 / 工具翻译成具体 API 形状。
///
/// 目前实现：[AnthropicMessagesClient]（Claude API 及 Anthropic 兼容端点）。
/// 将来接其它后端只需新增一个实现。
abstract class LlmClient {
  /// 完成一轮对话：带上 [messages] 与可用 [tools]，返回模型响应。
  ///
  /// 非流式实现即可满足 agent 循环；流式可在实现内部消化。
  Future<LlmResponse> complete({
    required List<ChatMessage> messages,
    List<ToolSpec> tools = const [],
  });
}
