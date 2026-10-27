import 'package:flutter/material.dart';

import '../../core/agent/llm_types.dart';
import '../../core/alarm/alarm_service.dart';
import '../../core/storage/app_store.dart';
import '../home/home_page.dart';
import '../settings/llm_settings_page.dart';
import 'assistant_store.dart';

/// AI 助手对话页 —— APP 的主页面（豆包式：打开即对话）。
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.app, required this.alarms});

  final AppStore app;
  final AlarmService alarms;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  late final AssistantStore _store;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _store = AssistantStore(widget.app, widget.alarms);
    _store.confirmTool = _confirmToolCall;
  }

  /// 写操作二次确认：列出工具与参数，用户点了确认才真正执行。
  Future<bool> _confirmToolCall(ToolCall call) async {
    final args = call.arguments.entries
        .map((e) => '· ${e.key}：${e.value}')
        .join('\n');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('助手想执行「${call.name}」'),
        content: Text(args.isEmpty ? '（无参数）' : args),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认执行'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  void dispose() {
    _store.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text;
    _inputCtrl.clear();
    await _store.send(text);
    _scrollToBottom();
  }

  /// 快捷指令：直接发送（豆包式一点即发）。
  Future<void> _sendPreset(String text) async {
    await _store.send(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_store, widget.app]),
      builder: (context, _) {
        if (_store.messages.isNotEmpty || _store.busy) _scrollToBottom();

        return Scaffold(
          appBar: AppBar(
            title: const Text('XNL 助手'),
            actions: [
              IconButton(
                icon: const Icon(Icons.widgets_outlined),
                tooltip: '全部功能',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => ToolsPage(store: widget.app)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: '接口配置',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => LlmSettingsPage(store: widget.app)),
                ),
              ),
              if (_store.messages.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: '清空对话',
                  onPressed: () => _store.clear(),
                ),
            ],
          ),
          body: Column(
            children: [
              if (!_store.isConfigured) _ConfigBanner(app: widget.app),
              if (_store.error != null) _ErrorBanner(
                message: _store.error!,
                onDismiss: () => _store.clear(),
              ),
              Expanded(
                child: _store.messages.isEmpty
                    ? _EmptyHint(
                        username: widget.app.isLoggedIn
                            ? widget.app.authUsername
                            : null,
                        onPreset: _sendPreset,
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemCount: _store.messages.length,
                        itemBuilder: (context, i) =>
                            _MessageView(message: _store.messages[i]),
                      ),
              ),
              if (_store.busy) const LinearProgressIndicator(minHeight: 2),
              _InputBar(
                controller: _inputCtrl,
                enabled: !_store.busy,
                onSend: _send,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    switch (message.role) {
      case ChatRole.user:
        return _Bubble(
          text: message.content,
          align: Alignment.centerRight,
          color: Theme.of(context).colorScheme.primaryContainer,
        );
      case ChatRole.assistant:
        if (message.toolCalls.isNotEmpty) {
          return _ToolCallChip(calls: message.toolCalls);
        }
        return _Bubble(
          text: message.content,
          align: Alignment.centerLeft,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        );
      case ChatRole.tool:
        return _ToolResultChip(message: message);
      case ChatRole.system:
        return const SizedBox.shrink();
    }
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.align,
    required this.color,
  });

  final String text;
  final Alignment align;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

class _ToolCallChip extends StatelessWidget {
  const _ToolCallChip({required this.calls});

  final List<ToolCall> calls;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in calls)
            Chip(
              avatar: Icon(Icons.build_circle_outlined,
                  size: 18, color: scheme.primary),
              label: Text('调用 ${c.name}'),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _ToolResultChip extends StatelessWidget {
  const _ToolResultChip({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = message.content.length > 120
        ? '${message.content.substring(0, 120)}…'
        : message.content;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            message.isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: message.isError ? scheme.error : scheme.outline,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottom),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: '比如：记一笔午饭 25 元',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigBanner extends StatelessWidget {
  const _ConfigBanner({required this.app});

  final AppStore app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LlmSettingsPage(store: app)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('尚未配置 LLM 接口 —— 点这里填写 API 地址与密钥'),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({this.username, required this.onPreset});

  final String? username;
  final ValueChanged<String> onPreset;

  static const _presets = [
    '记一笔午饭 25 元',
    '这个月花了多少',
    '写条明天开会的备忘录',
    '查一下买菜的备忘录',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor:
                  theme.colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome,
                  size: 40, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(
              username == null ? '你好，我是 XNL 助手' : '你好，$username',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '可以帮你记账、查账、管理备忘录\n试试下面的指令，或直接输入',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final p in _presets)
                  ActionChip(
                    label: Text(p),
                    onPressed: () => onPreset(p),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
