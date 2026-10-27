import 'llm_types.dart';

/// LLM 接入配置（Anthropic 兼容端点）。
///
/// [baseUrl] 取 API 根地址，例如 `https://api.anthropic.com`；
/// 带不带 `/v1` 都行，会自动归一到 `/v1/messages`。
class LlmConfig {
  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  /// Messages API 协议版本头。
  static const anthropicVersion = '2023-06-01';

  bool get isConfigured => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  /// Messages 端点：`…/v1/messages`。
  Uri messagesUri() {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final base = root.endsWith('/v1') ? root : '$root/v1';
    return Uri.parse('$base/messages');
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'x-api-key': apiKey.trim(),
        'anthropic-version': anthropicVersion,
      };

  static const empty = LlmConfig(baseUrl: '', apiKey: '', model: '');
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
