import 'dart:convert';

import 'llm_types.dart';

/// 一个可被模型调用的工具。
///
/// [execute] 接收已解析的参数 Map，返回结果约定为 JSON 字符串；
/// 抛出的异常会被包装成 `is_error` 的 tool result 回传给模型。
class AgentTool {
  const AgentTool({required this.spec, required this.execute});

  final ToolSpec spec;
  final Future<String> Function(Map<String, dynamic> arguments) execute;

  String get name => spec.name;
}

/// 工具注册表：维护可用工具，负责查找与执行。
class ToolRegistry {
  ToolRegistry(Iterable<AgentTool> tools)
      : _tools = {for (final t in tools) t.name: t};

  final Map<String, AgentTool> _tools;

  List<ToolSpec> get specs => [for (final t in _tools.values) t.spec];

  AgentTool? find(String name) => _tools[name];

  void register(AgentTool tool) => _tools[tool.name] = tool;

  /// 执行一次工具调用；任何失败都转成 error 结果而不是抛出，
  /// 让模型有机会自我纠正。
  Future<ToolResult> run(ToolCall call) async {
    final tool = _tools[call.name];
    if (tool == null) {
      return ToolResult(
        toolCallId: call.id,
        isError: true,
        content: jsonEncode({'error': '未知工具：${call.name}'}),
      );
    }
    try {
      final output = await tool.execute(call.arguments);
      return ToolResult(toolCallId: call.id, content: output);
    } on Exception catch (e) {
      return ToolResult(
        toolCallId: call.id,
        isError: true,
        content: jsonEncode({'error': e.toString()}),
      );
    }
  }
}
