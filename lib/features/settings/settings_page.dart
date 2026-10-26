import 'package:flutter/material.dart';

import '../../core/storage/app_store.dart';
import 'llm_settings_page.dart';

/// 设置：外观、数据管理、关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('外观', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: RadioGroup<ThemeMode>(
                  groupValue: store.themeMode,
                  onChanged: (v) {
                    if (v != null) store.setThemeMode(v);
                  },
                  child: const Column(
                    children: [
                      RadioListTile<ThemeMode>(
                        title: Text('跟随系统'),
                        value: ThemeMode.system,
                      ),
                      RadioListTile<ThemeMode>(
                        title: Text('浅色'),
                        value: ThemeMode.light,
                      ),
                      RadioListTile<ThemeMode>(
                        title: Text('深色'),
                        value: ThemeMode.dark,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('数据', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(Icons.delete_forever_outlined,
                      color: theme.colorScheme.error),
                  title: const Text('清空全部数据'),
                  subtitle: const Text('删除所有备忘录与账单，不可恢复'),
                  onTap: () => _confirmClear(context),
                ),
              ),
              const SizedBox(height: 24),
              Text('AI 助手', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('LLM 接口配置'),
                  subtitle: Text(
                    store.llmConfig.isConfigured
                        ? '已配置：${store.llmConfig.model}'
                        : '未配置',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => LlmSettingsPage(store: store)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('关于', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              const Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('XNL 工具箱'),
                      subtitle: Text('版本 1.0.1'),
                    ),
                    ListTile(
                      leading: Icon(Icons.flutter_dash),
                      title: Text('基于 Flutter 构建'),
                      subtitle: Text('数据仅保存在本机'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部数据？'),
        content: const Text('所有备忘录和账单都会被删除，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await store.clearAll();
    }
  }
}
