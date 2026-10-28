import 'package:flutter/material.dart';

import '../../core/agent/llm_types.dart';
import '../../core/alarm/alarm_service.dart';
import '../../core/storage/app_store.dart';
import '../../core/voice/tts_player.dart';
import '../../core/voice/voice_api.dart';
import '../../core/voice/voice_recorder.dart';
import '../home/home_page.dart';
import '../settings/llm_settings_page.dart';
import 'assistant_store.dart';

/// AI 助手对话页 —— APP 的主页面（豆包式：打开即对话，支持语音与流式输出）。
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
  final _recorder = VoiceRecorder();
  final _tts = TtsPlayer();
  bool _recording = false;
  bool _transcribing = false;

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
    _recorder.dispose();
    _tts.dispose();
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
    await _maybeSpeak();
  }

  /// 快捷指令：直接发送（豆包式一点即发）。
  Future<void> _sendPreset(String text) async {
    await _store.send(text);
    _scrollToBottom();
    await _maybeSpeak();
  }

  /// 语音输入：点一下开始录音，再点一下停止并识别，识别结果直接发送。
  Future<void> _toggleMic() async {
    if (_recording) {
      setState(() => _recording = false);
      final wav = await _recorder.stop();
      if (wav == null || !mounted) return;
      setState(() => _transcribing = true);
      try {
        final text = await AsrClient(
          apiKey: widget.app.llmConfig.apiKey,
        ).transcribe(wav);
        if (!mounted) return;
        if (text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有听清，请再说一遍')),
          );
          return;
        }
        await _store.send(text);
        _scrollToBottom();
        await _maybeSpeak();
      } on VoiceApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('语音识别失败：${e.message}')),
          );
        }
      } on Exception catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('语音识别失败：$e')),
          );
        }
      } finally {
        if (mounted) setState(() => _transcribing = false);
      }
      return;
    }

    if (!widget.app.llmConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在「接口配置」里填写 API Key')),
      );
      return;
    }
    await _tts.stop();
    if (!await _recorder.ensurePermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有麦克风权限，无法语音输入')),
        );
      }
      return;
    }
    await _recorder.start();
    if (mounted) setState(() => _recording = true);
  }

  /// 语音播报开关（豆包式）：关掉时立刻停止正在播放的语音。
  Future<void> _toggleVoiceReply() async {
    final next = !widget.app.voiceReplyEnabled;
    await widget.app.setVoiceReplyEnabled(next);
    if (!next) await _tts.stop();
  }

  /// 回复完成后播报最后一条助手文本（开关开着才播）。
  Future<void> _maybeSpeak() async {
    if (!widget.app.voiceReplyEnabled) return;
    final apiKey = widget.app.llmConfig.apiKey;
    if (apiKey.isEmpty) return;
    final msgs = _store.messages;
    for (var i = msgs.length - 1; i >= 0; i--) {
      final m = msgs[i];
      if (m.role == ChatRole.assistant && m.content.trim().isNotEmpty) {
        try {
          final wav = await TtsClient(apiKey: apiKey).synthesize(m.content);
          await _tts.play(wav);
        } on Exception {
          // 播报失败不打扰对话，静默忽略
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_store, widget.app]),
      builder: (context, _) {
        if (_store.messages.isNotEmpty || _store.busy) _scrollToBottom();

        final streaming = _store.streamingText;
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          appBar: AppBar(
            titleSpacing: 16,
            title: const Row(
              children: [
                _AssistantAvatar(size: 32),
                SizedBox(width: 10),
                Text('XNL 助手'),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(widget.app.voiceReplyEnabled
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded),
                tooltip: widget.app.voiceReplyEnabled ? '语音播报：开' : '语音播报：关',
                onPressed: _toggleVoiceReply,
              ),
              IconButton(
                icon: const Icon(Icons.widgets_outlined),
                tooltip: '全部功能',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => ToolsPage(store: widget.app, alarms: widget.alarms)),
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
                child: _store.messages.isEmpty && streaming == null
                    ? _EmptyHint(
                        username: widget.app.isLoggedIn
                            ? widget.app.authUsername
                            : null,
                        onPreset: _sendPreset,
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: _store.messages.length +
                            ((streaming != null || _store.busy) ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i < _store.messages.length) {
                            return _MessageView(message: _store.messages[i]);
                          }
                          // 末尾：流式草稿气泡 / 打字中指示
                          return _StreamingView(
                            text: streaming,
                            typing: streaming == null,
                          );
                        },
                      ),
              ),
              _InputBar(
                controller: _inputCtrl,
                enabled: !_store.busy,
                recording: _recording,
                transcribing: _transcribing,
                onMic: _toggleMic,
                onSend: _send,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 助手头像：渐变圆底 + 星光图标。
class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar({this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        size: size * 0.55,
        color: scheme.onPrimary,
      ),
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
        return _Row(
          isUser: true,
          children: [
            _Bubble(
              text: message.content,
              isUser: true,
            ),
          ],
        );
      case ChatRole.assistant:
        return _Row(
          children: [
            if (message.content.isNotEmpty) ...[
              _Bubble(text: message.content, isUser: false),
            ],
            if (message.toolCalls.isNotEmpty) ...[
              if (message.content.isNotEmpty) const SizedBox(height: 6),
              _ToolCallChip(calls: message.toolCalls),
            ],
          ],
        );
      case ChatRole.tool:
        return Padding(
          padding: const EdgeInsets.only(left: 38, top: 2, bottom: 2),
          child: _ToolResultChip(message: message),
        );
      case ChatRole.system:
        return const SizedBox.shrink();
    }
  }
}

/// 消息行：助手带头像靠左，用户靠右。
class _Row extends StatelessWidget {
  const _Row({required this.children, this.isUser = false});

  final List<Widget> children;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final row = Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: children,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const _AssistantAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(child: row),
        ],
      ),
    );
  }
}

/// 对话气泡：用户主色实心，助手浅底描边。
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      decoration: BoxDecoration(
        gradient: isUser
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.primary.withValues(alpha: 0.82)],
              )
            : null,
        color: isUser ? null : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isUser ? 20 : 6),
          bottomRight: Radius.circular(isUser ? 6 : 20),
        ),
        border: isUser
            ? null
            : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: (isUser ? scheme.primary : scheme.shadow)
                .withValues(alpha: isUser ? 0.18 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isUser ? scheme.onPrimary : scheme.onSurface,
              height: 1.45,
            ),
      ),
    );
  }
}

/// 流式输出气泡：文本随打随出，尾部光标闪烁；还没有文本时显示打字动画。
class _StreamingView extends StatelessWidget {
  const _StreamingView({required this.text, required this.typing});

  final String? text;
  final bool typing;

  @override
  Widget build(BuildContext context) {
    if (typing) {
      return const _Row(children: [_TypingDots()]);
    }
    return _Row(
      children: [
        _Bubble(
          text: text!,
          isUser: false,
        ),
      ],
    );
  }
}

/// 打字中三点动画（仅忙碌时出现，闲时不占帧）。
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(20),
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Opacity(
                    opacity: 0.35 +
                        0.65 *
                            ((1 -
                                    (((_ctrl.value + i * 0.2) % 1.0) - 0.5)
                                        .abs() *
                                        2)
                                .clamp(0.0, 1.0)),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in calls)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: scheme.secondary.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.build_circle_outlined,
                    size: 16, color: scheme.secondary),
                const SizedBox(width: 6),
                Text(
                  '调用 ${c.name}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                ),
              ],
            ),
          ),
      ],
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

    return Row(
      children: [
        Icon(
          message.isError ? Icons.error_outline : Icons.check_circle_outline,
          size: 15,
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.recording,
    required this.transcribing,
    required this.onMic,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool recording;
  final bool transcribing;
  final VoidCallback onMic;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 12, 10 + bottom),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border:
                Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
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
                  decoration: InputDecoration(
                    hintText: recording
                        ? '正在录音，点一下麦克风结束'
                        : (transcribing ? '正在识别…' : '比如：记一笔午饭 25 元'),
                    border: InputBorder.none,
                    filled: false,
                    isDense: true,
                    hintStyle: TextStyle(color: scheme.outline),
                  ),
                ),
              ),
              _MicButton(
                recording: recording,
                transcribing: transcribing,
                enabled: enabled,
                onTap: onMic,
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: enabled ? onSend : null,
                style: IconButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(10),
                ),
                icon: const Icon(Icons.send_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 麦克风按钮：录音中变红色停止钮并轻微呼吸动画。
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.recording,
    required this.transcribing,
    required this.enabled,
    required this.onTap,
  });

  final bool recording;
  final bool transcribing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = transcribing
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            recording ? Icons.stop_rounded : Icons.mic_none_rounded,
            size: 22,
            color: recording ? scheme.onErrorContainer : scheme.onSurfaceVariant,
          );
    return IconButton(
      onPressed: enabled ? onTap : null,
      tooltip: recording ? '结束并识别' : '语音输入',
      style: IconButton.styleFrom(
        backgroundColor:
            recording ? scheme.errorContainer : Colors.transparent,
        shape: const CircleBorder(),
      ),
      icon: recording ? _Pulsing(child: icon) : icon,
    );
  }
}

/// 录音时的呼吸缩放动画。
class _Pulsing extends StatefulWidget {
  const _Pulsing({required this.child});

  final Widget child;

  @override
  State<_Pulsing> createState() => _PulsingState();
}

class _PulsingState extends State<_Pulsing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.12).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: widget.child,
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
                child: Text('尚未配置 LLM 接口 —— 点这里填写 API Key'),
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
    (Icons.receipt_long_rounded, '记一笔午饭 25 元'),
    (Icons.pie_chart_rounded, '这个月花了多少'),
    (Icons.edit_note_rounded, '写条明天开会的备忘录'),
    (Icons.search_rounded, '查一下买菜的备忘录'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _AssistantAvatar(size: 72),
            const SizedBox(height: 18),
            Text(
              username == null ? '你好，我是 XNL 助手' : '你好，$username',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '可以帮你记账、查账、管理备忘录\n试试下面的指令，或直接输入',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.outline, height: 1.6),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final (icon, label) in _presets)
                  ActionChip(
                    avatar: Icon(icon, size: 18, color: scheme.primary),
                    label: Text(label),
                    onPressed: () => onPreset(label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
