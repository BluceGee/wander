import 'package:flutter/material.dart';

import '../../core/storage/app_store.dart';

/// AI 助手接口配置：只需填 API Key（端点与模型已写死在程序里）。
///
/// 密钥只保存在本机加密存储，不会写入代码仓库。
class LlmSettingsPage extends StatefulWidget {
  const LlmSettingsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends State<LlmSettingsPage> {
  late final TextEditingController _apiKeyCtrl;
  bool _obscureKey = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _apiKeyCtrl = TextEditingController(text: widget.store.llmConfig.apiKey);
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.store.setLlmApiKey(_apiKeyCtrl.text);
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
          Text('API Key', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'tp-…',
              helperText: '保存在系统加密存储（Android Keystore），请勿分享截图',
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
                    '· 接口地址与模型已内置（MiMo 平台），只需填 API Key\n'
                    '· 语音输入（mimo-v2.5-asr）与语音播报（mimo-v2.5-tts）使用同一个 Key\n'
                    '· Key 保存在系统加密存储（Android Keystore），不进备份、卸载即清除\n'
                    '· 请求会把你问句里的相关内容（账目/备忘录片段）与语音发给 MiMo 平台\n'
                    '· 正式对外分发时应改为后端代理转发，APK 内永远不带密钥',
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
