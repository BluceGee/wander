import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/agent/agent_service.dart';
import '../../core/agent/agent_tool.dart';
import '../../core/agent/llm_types.dart';
import '../../core/agent/openai_compat_client.dart';
import '../../core/alarm/alarm_service.dart';
import '../../core/network/pinned_client.dart';
import '../../core/network/server_config.dart';
import '../../core/storage/app_store.dart';
import 'app_tools.dart';

/// AI 助手会话状态：持有对话历史，驱动 agent 循环。
class AssistantStore extends ChangeNotifier {
  AssistantStore(this._app, this._alarms);

  final AppStore _app;
  final AlarmService _alarms;
  final List<ChatMessage> _messages = [];

  bool _busy = false;
  String? _error;

  /// 写操作确认回调，由界面注入（弹对话框）。不设置则放行。
  Future<bool> Function(ToolCall call)? confirmTool;

  /// 对外展示的对话历史（不含 system 提示词）。
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool get busy => _busy;

  String? get error => _error;

  bool get isConfigured => _app.llmConfig.isConfigured;

  /// 系统提示词：角色、工具范围、日期（供"今天/昨天"等相对表达换算）。
  String buildSystemPrompt() {
    final today = DateFormat('yyyy-MM-dd（EEEE）').format(DateTime.now());
    return '''
你是「XNL 工具箱」内置的 AI 助手，帮用户打理工具箱里的备忘录、账单和闹钟。用户用中文提问，你用中文回答。

今天是 $today。涉及"今天/昨天/明天/本周"等相对日期时，换算成具体日期再调用工具。

你可以调用工具来：
- 备忘录：查询（list_memos）、新建（create_memo）、删除（delete_memo）
- 记账：记一笔（add_expense）、查账单（query_expenses）、月度汇总（get_month_summary）
- 闹钟：查询（list_alarms）、新建（create_alarm）、删除（delete_alarm）、开关（switch_alarm）

使用规则：
- 涉及记账/备忘录/闹钟数据的操作，必须通过工具查询或写入，不要凭空编造数字。
- 写操作（记一笔、新建/删除备忘录、新建/删除闹钟）执行后，用一句话向用户确认结果。
- 汇报金额时保留两位小数，带上单位。
- 闹钟时间用 24 小时制回显（如 07:30）；用户说「7 点」而没说上午下午时按 07:00 理解，拿不准就问一句。
- 与工具箱无关的问题（闲聊、知识问答），直接回答，不需要调用工具。
- 不确定用户意图时先问清楚，不要猜着写数据。''';
  }

  /// 发送一条用户消息并跑完 agent 循环。
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;

    if (!isConfigured) {
      _error = '尚未配置 LLM 接口：请到「设置 → AI 助手」填写 API 地址与密钥。';
      notifyListeners();
      return;
    }

    _error = null;
    _messages.add(ChatMessage.user(trimmed));
    _busy = true;
    notifyListeners();

    final service = AgentService(
      llm: OpenAiCompatClient(
        config: _app.llmConfig,
        // 与账号服务共用证书固定：Base URL 填代理地址时自签证书也能过
        httpClient: createPinnedClient(ServerConfig.certPin),
      ),
      registry: ToolRegistry(buildAppTools(_app, _alarms)),
      systemPrompt: buildSystemPrompt(),
      approveTool: confirmTool,
    );

    try {
      await service.run(
        history: _messages,
        onMessage: (m) {
          // 工具调用与结果逐条刷新 UI，让用户看见助手在干什么
          notifyListeners();
        },
      );
    } on LlmException catch (e) {
      _error = e.toString();
    } on Exception catch (e) {
      _error = '调用失败：$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clear() {
    _messages.clear();
    _error = null;
    notifyListeners();
  }
}
