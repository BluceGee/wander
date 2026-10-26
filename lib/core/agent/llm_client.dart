import 'llm_types.dart';

/// LLM 接入配置（如 MiMo 平台）。
///
/// [baseUrl] 取平台的 API 根地址（不含 `/chat/completions`，
/// 一般以 `/v1` 结尾），例如 `https://api.example.com/v1`。
class LlmConfig {
  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  bool get isConfigured => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  /// 去掉末尾斜杠后的根地址。
  Uri chatCompletionsUri() {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$root/chat/completions');
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      };

  static const empty = LlmConfig(baseUrl: '', apiKey: '', model: '');
}

/// 供应商适配层接口：把框架内的消息 / 工具翻译成具体 API 形状。
///
/// 目前实现：[OpenAiCompatClient]（MiMo 等 OpenAI 兼容平台）。
/// 将来接其它后端（如自建 ZeroClaw 网关）只需新增一个实现。
abstract class LlmClient {
  /// 完成一轮对话：带上 [messages] 与可用 [tools]，返回模型响应。
  ///
  /// 非流式实现即可满足 agent 循环；流式可在实现内部消化。
  Future<LlmResponse> complete({
    required List<ChatMessage> messages,
    List<ToolSpec> tools = const [],
  });
}
