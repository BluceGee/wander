import 'package:flutter/material.dart';

import '../../core/storage/app_store.dart';

/// AI 助手接口配置：OpenAI 兼容端点（如 MiMo 平台）。
///
/// 密钥只保存在本机 shared_preferences，不会写入代码仓库。
class LlmSettingsPage extends StatefulWidget {
  const LlmSettingsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends State<LlmSettingsPage> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _apiKeyCtrl;
  bool _obscureKey = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final config = widget.store.llmConfig;
    _baseUrlCtrl = TextEditingController(text: config.baseUrl);
    _modelCtrl = TextEditingController(text: config.model);
    _apiKeyCtrl = TextEditingController(text: config.apiKey);
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.store.setLlmConfig(
      baseUrl: _baseUrlCtrl.text,
      apiKey: _apiKeyCtrl.text,
      model: _modelCtrl.text,
    );
    if (mounted) {
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 助手接口'),
        actions: [
          TextButton.icon(
            onPressed: _dirty || !widget.store.llmConfig.isConfigured
                ? _save
                : null,
            icon: const Icon(Icons.check),
            label: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('LLM 接口（OpenAI 兼容）', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'API 地址',
              hintText: '例如 https://api.example.com/v1',
              helperText: '平台控制台里的 Base URL，一般以 /v1 结尾；会自动拼 /chat/completions',
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: '模型名',
              hintText: '例如 mimo-v2.6-pro',
              helperText: '平台文档里的 model id',
            ),
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-…',
              helperText: '只保存在本机，请勿分享截图或提交到代码仓库',
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            onChanged: (_) => setState(() => _dirty = true),
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('说明', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    '· 支持任何 OpenAI 兼容接口（/chat/completions + function calling）\n'
                    '· 模型需要支持工具调用（tools/tool_calls），否则助手无法操作备忘录与账单\n'
                    '· Key 存在本机，卸载 APP 即清除；正式对外分发时应改为后端代理转发',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
