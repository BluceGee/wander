import 'dart:convert';

import 'package:intl/intl.dart';

import '../../core/agent/agent_tool.dart';
import '../../core/agent/llm_types.dart';
import '../../core/alarm/alarm_service.dart';
import '../../core/models/alarm.dart';
import '../../core/models/expense.dart';
import '../../core/models/memo.dart';
import '../../core/storage/app_store.dart';
import '../../core/utils/clock_parse.dart';
import '../../core/utils/date_hint.dart';

/// 框架内置工具集：直接操作 [AppStore] 里的备忘录、账单与闹钟。
///
/// 返回值统一为 JSON 字符串；抛异常即代表工具失败（会以
/// `is_error` 回传给模型，让它自行纠正参数）。
List<AgentTool> buildAppTools(AppStore store, AlarmService alarms) {
  return [
    AgentTool(
      spec: const ToolSpec(
        name: 'list_memos',
        description: '查询备忘录列表。可选关键词过滤标题和内容；不传则返回全部（置顶优先）。',
        parameters: {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': '搜索关键词，匹配标题与正文；不传表示全部',
            },
          },
          'required': [],
        },
      ),
      execute: (args) async {
        final query = (args['query'] as String? ?? '').trim();
        final memos = store.memos.where((m) {
          if (query.isEmpty) return true;
          return m.title.contains(query) || m.content.contains(query);
        }).toList();
        return jsonEncode({
          'count': memos.length,
          'memos': [
            for (final m in memos)
              {
                'id': m.id,
                'title': m.title,
                'preview': m.content.length > 60
                    ? '${m.content.substring(0, 60)}…'
                    : m.content,
                'pinned': m.pinned,
                'updatedAt': m.updatedAt.toIso8601String(),
              }
          ],
        });
      },
    ),
    AgentTool(
      spec: const ToolSpec(
        name: 'create_memo',
        description: '新建一条备忘录。',
        parameters: {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': '标题（可为空字符串）'},
            'content': {'type': 'string', 'description': '正文内容'},
          },
          'required': ['content'],
        },
        requiresConfirmation: true,
      ),
      execute: (args) async {
        final title = (args['title'] as String? ?? '').trim();
        final content = (args['content'] as String? ?? '').trim();
        if (content.isEmpty && title.isEmpty) {
          throw const FormatException('title 与 content 不能都为空');
        }
        final memo = Memo.create(title: title, content: content);
        await store.addMemo(memo);
        return jsonEncode({'ok': true, 'id': memo.id, 'title': memo.title});
      },
    ),
    AgentTool(
      spec: const ToolSpec(
        name: 'delete_memo',
        description: '按 id 删除一条备忘录。删除前请向用户确认。',
        parameters: {
          'type': 'object',
          'properties': {
            'id': {'type': 'string', 'description': '备忘录 id（来自 list_memos）'},
          },
          'required': ['id'],
        },
        requiresConfirmation: true,
      ),
      execute: (args) async {
        final id = (args['id'] as String? ?? '').trim();
        if (id.isEmpty) throw const FormatException('缺少 id');
        if (!store.memos.any((m) => m.id == id)) {
          throw FormatException('找不到 id 为 $id 的备忘录');
        }
        await store.deleteMemo(id);
        return jsonEncode({'ok': true, 'deleted': id});
      },
    ),
    AgentTool(
      spec: const ToolSpec(
        name: 'add_expense',
        description: '记一笔账（支出或收入）。',
        parameters: {
          'type': 'object',
          'properties': {
            'amount': {'type': 'number', 'description': '金额，必须大于 0'},
            'is_expense': {
              'type': 'boolean',
              'description': 'true=支出，false=收入。默认 true',
            },
            'category': {
              'type': 'string',
              'description': '分类。支出：餐饮/交通/购物/娱乐/居家/医疗/教育/其他；'
                  '收入：工资/奖金/理财/红包/其他',
            },
            'note': {'type': 'string', 'description': '备注，可选'},
            'date': {
              'type': 'string',
              'description': '日期。支持 YYYY-MM-DD，或口语：今天/昨天/前天/明天/'
                  '3号/上周三/10月1日；默认今天。结果里会回显归一后的日期',
            },
          },
          'required': ['amount', 'category'],
        },
        requiresConfirmation: true,
      ),
      execute: (args) async {
        final amount = (args['amount'] as num?)?.toDouble();
        if (amount == null || amount <= 0) {
          throw const FormatException('amount 必须是大于 0 的数字');
        }
        final isExpense = args['is_expense'] as bool? ?? true;
        final allowed = isExpense
            ? ExpenseCategory.expenseCategories.map((c) => c.name)
            : ExpenseCategory.incomeCategories.map((c) => c.name);
        final category = (args['category'] as String? ?? '其他').trim();
        if (!allowed.contains(category)) {
          throw FormatException(
              'category「$category」无效。${isExpense ? '支出' : '收入'}可选：${allowed.join('/')}');
        }
        final dateRaw = (args['date'] as String? ?? '').trim();
        DateTime date = DateTime.now();
        if (dateRaw.isNotEmpty) {
          final parsed = tryParseDateHint(dateRaw);
          if (parsed == null) {
            throw FormatException(
                'date「$dateRaw」无法识别。可选：2026-10-26 / 今天 / 昨天 / 前天 / '
                '明天 / 3号 / 上周三 / 10月1日');
          }
          date = parsed;
        }
        final record = ExpenseRecord.create(
          amount: amount,
          isExpense: isExpense,
          category: category,
          note: (args['note'] as String? ?? '').trim(),
          date: date,
        );
        await store.addExpense(record);
        return jsonEncode({
          'ok': true,
          'id': record.id,
          'type': isExpense ? '支出' : '收入',
          'amount': amount,
          'category': category,
          'date': DateFormat('yyyy-MM-dd').format(date),
        });
      },
    ),
    AgentTool(
      spec: const ToolSpec(
        name: 'query_expenses',
        description: '查询账单。按月查询（默认本月），可选只看支出或收入；返回明细与汇总。',
        parameters: {
          'type': 'object',
          'properties': {
            'month': {
              'type': 'string',
              'description': '月份 YYYY-MM，如 2026-10；默认当月',
            },
            'type': {
              'type': 'string',
              'enum': ['expense', 'income', 'all'],
              'description': '过滤类型：expense=只看支出，income=只看收入，all=全部。默认 all',
            },
            'category': {'type': 'string', 'description': '按分类过滤，可选'},
          },
          'required': [],
        },
      ),
      execute: (args) async {
        final now = DateTime.now();
        final monthRaw = (args['month'] as String? ?? '').trim();
        DateTime month = DateTime(now.year, now.month);
        if (monthRaw.isNotEmpty) {
          try {
            final parsed = DateFormat('yyyy-MM').parseStrict(monthRaw);
            month = DateTime(parsed.year, parsed.month);
          } on FormatException {
            throw FormatException('month「$monthRaw」格式错误，应为 YYYY-MM');
          }
        }
        final type = (args['type'] as String? ?? 'all').trim();
        final category = (args['category'] as String? ?? '').trim();

        var records = store.expensesOfMonth(month);
        if (type == 'expense') {
          records = records.where((r) => r.isExpense).toList();
        } else if (type == 'income') {
          records = records.where((r) => !r.isExpense).toList();
        }
        if (category.isNotEmpty) {
          records = records.where((r) => r.category == category).toList();
        }
        final summary = ExpenseSummary.of(records);

        return jsonEncode({
          'month': DateFormat('yyyy-MM').format(month),
          'count': records.length,
          'total_expense': summary.totalExpense,
          'total_income': summary.totalIncome,
          'balance': summary.balance,
          'by_category': summary.byCategory,
          'records': [
            for (final r in records)
              {
                'id': r.id,
                'type': r.isExpense ? '支出' : '收入',
                'amount': r.amount,
                'category': r.category,
                'note': r.note,
                'date': DateFormat('yyyy-MM-dd').format(r.date),
              }
          ],
        });
      },
    ),
    AgentTool(
      spec: const ToolSpec(
        name: 'get_month_summary',
        description: '获取某月收支汇总（支出/收入/结余/分类占比），不返回明细。适合回答「这个月花了多少」这类问题。',
        parameters: {
          'type': 'object',
          'properties': {
            'month': {
              'type': 'string',
              'description': '月份 YYYY-MM，默认当月',
            },
          },
          'required': [],
        },
      ),
      execute: (args) async {
        final now = DateTime.now();
        final monthRaw = (args['month'] as String? ?? '').trim();
        DateTime month = DateTime(now.year, now.month);
        if (monthRaw.isNotEmpty) {
          try {
            final parsed = DateFormat('yyyy-MM').parseStrict(monthRaw);
            month = DateTime(parsed.year, parsed.month);
          } on FormatException {
            throw FormatException('month「$monthRaw」格式错误，应为 YYYY-MM');
          }
        }
        final summary = ExpenseSummary.of(store.expensesOfMonth(month));
        return jsonEncode({
          'month': DateFormat('yyyy-MM').format(month),
          'total_expense': summary.totalExpense,
          'total_income': summary.totalIncome,
          'balance': summary.balance,
          'by_category': summary.byCategory,
        });
      },
    ),
    AgentTool(
      spec: const ToolSpec(
        name: 'list_alarms',
        description: '查询闹钟列表，含开关状态、重复方式、关闭方式、贪睡设置与下次响铃时间。',
        parameters: {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      ),
      execute: (args) async {
        final all = store.alarms;
        return jsonEncode({
          'count': all.length,
          'alarms': [
            for (final a in all)
              {
                'id': a.id,
                'label': a.label,
                'time': a.timeLabel,
                'enabled': a.enabled,
                'repeat': _repeatLabel(a),
                'next_ring':
                    a.enabled ? a.nextTrigger()?.toIso8601String() : null,
                'dismiss': a.dismissMethod.label,
                'snooze': a.snoozeEnabled
                    ? '${a.snoozeMinutes}分钟后再响，最多${a.snoozeLimit}次'
                    : '关闭',
                'ringtone': a.ringtoneName,
              }
          ],
        });
      },
    ),
    AgentTool(
      spec: const ToolSpec(
        name: 'create_alarm',
        description: '新建一个闹钟。time 支持 07:30 / 7点半 / 晚上9点15 等说法；'
            'date 给一次性日期（口语如「明天」「10月1日」），days 给每周重复日'
            '（1=周一 … 7=周日），两者互斥且都不给表示每天重复。'
            '用户没说关闭方式时保持默认 tap（点一下关闭）。',
        parameters: {
          'type': 'object',
          'properties': {
            'time': {
              'type': 'string',
              'description': '必填。响铃时间，如 07:30、7点半、晚上9点15',
            },
            'label': {'type': 'string', 'description': '备注名，可选，如「晨跑」'},
            'date': {
              'type': 'string',
              'description': '一次性日期：YYYY-MM-DD 或 明天/3号/10月1日。与 days 互斥',
            },
            'days': {
              'type': 'array',
              'items': {'type': 'integer'},
              'description': '每周重复日 1~7（1=周一 … 7=周日）。与 date 互斥',
            },
            'dismiss_method': {
              'type': 'string',
              'enum': ['tap', 'hold', 'math', 'typing', 'shake'],
              'description': '关闭方式：点一下/长按/算题/输入文字/摇一摇。默认 tap',
            },
            'snooze_enabled': {
              'type': 'boolean',
              'description': '是否允许贪睡（暂时关闭后稍后再响）。默认 true',
            },
            'snooze_minutes': {
              'type': 'integer',
              'description': '贪睡几分钟后再响，1~60，默认 9',
            },
            'snooze_limit': {
              'type': 'integer',
              'description': '最多贪睡次数，0~20，默认 3',
            },
          },
          'required': ['time'],
        },
        requiresConfirmation: true,
      ),
      execute: (args) async {
        final timeRaw = (args['time'] as String? ?? '').trim();
        if (timeRaw.isEmpty) throw const FormatException('缺少 time');
        final t = tryParseClockTime(timeRaw);
        if (t == null) {
          throw FormatException(
              'time「$timeRaw」无法识别。可选：07:30 / 7点半 / 晚上9点15');
        }

        final dateRaw = (args['date'] as String? ?? '').trim();
        final daysRaw = (args['days'] as List?) ?? const [];
        if (dateRaw.isNotEmpty && daysRaw.isNotEmpty) {
          throw const FormatException(
              'date 与 days 不能同时给：date 是一次性闹钟，days 是每周重复');
        }
        DateTime? date;
        if (dateRaw.isNotEmpty) {
          date = tryParseDateHint(dateRaw);
          if (date == null) {
            throw FormatException('date「$dateRaw」无法识别。'
                '可选：2026-11-01 / 明天 / 3号 / 10月1日');
          }
        }
        final days = <int>[];
        for (final d in daysRaw) {
          final n = (d as num?)?.toInt();
          if (n == null || n < 1 || n > 7) {
            throw FormatException('days 只能是 1~7（1=周一 … 7=周日），收到：$d');
          }
          days.add(n);
        }

        final dismissRaw = (args['dismiss_method'] as String? ?? 'tap').trim();
        final dismiss = AlarmDismissMethod.values.firstWhere(
          (e) => e.name == dismissRaw,
          orElse: () => throw FormatException('dismiss_method「$dismissRaw」无效。'
              '可选：tap/hold/math/typing/shake'),
        );

        final snoozeEnabled = args['snooze_enabled'] as bool? ?? true;
        final snoozeMinutes = (args['snooze_minutes'] as num?)?.toInt() ?? 9;
        final snoozeLimit = (args['snooze_limit'] as num?)?.toInt() ?? 3;
        if (snoozeMinutes < 1 || snoozeMinutes > 60) {
          throw FormatException('snooze_minutes 需在 1~60，收到：$snoozeMinutes');
        }
        if (snoozeLimit < 0 || snoozeLimit > 20) {
          throw FormatException('snooze_limit 需在 0~20，收到：$snoozeLimit');
        }

        final record = AlarmRecord.create(
          hour: t.hour,
          minute: t.minute,
          label: (args['label'] as String? ?? '').trim(),
          date: date,
          daysOfWeek: days,
          dismissMethod: dismiss,
          snoozeEnabled: snoozeEnabled,
          snoozeMinutes: snoozeMinutes,
          snoozeLimit: snoozeLimit,
        );
        await alarms.save(record);
        final saved = store.alarmById(record.id) ?? record;
        return jsonEncode({
          'ok': true,
          'id': saved.id,
          'time': saved.timeLabel,
          'repeat': _repeatLabel(saved),
          'label': saved.label,
          'dismiss': saved.dismissMethod.label,
          'snooze': saved.snoozeEnabled
              ? '${saved.snoozeMinutes}分钟后再响，最多${saved.snoozeLimit}次'
              : '关闭',
          'enabled': saved.enabled,
          'next_ring': saved.nextTrigger()?.toIso8601String(),
        });
      },
    ),
    AgentTool(
      spec: const ToolSpec(
        name: 'delete_alarm',
        description: '删除一个闹钟。优先用 id（来自 list_alarms）；'
            '也可以给 time（如 07:30）按时间找唯一匹配。',
        parameters: {
          'type': 'object',
          'properties': {
            'id': {'type': 'string', 'description': '闹钟 id（来自 list_alarms）'},
            'time': {
              'type': 'string',
              'description': '按时间找闹钟，如 07:30 / 7点半。id 与 time 二选一',
            },
          },
          'required': [],
        },
        requiresConfirmation: true,
      ),
      execute: (args) async {
        final target = _findAlarm(store, args);
        await alarms.remove(target.id);
        return jsonEncode({
          'ok': true,
          'deleted': target.id,
          'time': target.timeLabel,
          'label': target.label,
        });
      },
    ),
    AgentTool(
      spec: const ToolSpec(
        name: 'switch_alarm',
        description: '开启或关闭一个闹钟。优先用 id；也可以给 time（如 07:30）'
            '按时间找唯一匹配。',
        parameters: {
          'type': 'object',
          'properties': {
            'id': {'type': 'string', 'description': '闹钟 id（来自 list_alarms）'},
            'time': {
              'type': 'string',
              'description': '按时间找闹钟，如 07:30 / 7点半。id 与 time 二选一',
            },
            'enabled': {
              'type': 'boolean',
              'description': 'true=开启，false=关闭',
            },
          },
          'required': ['enabled'],
        },
      ),
      execute: (args) async {
        final enabled = args['enabled'] as bool?;
        if (enabled == null) throw const FormatException('缺少 enabled');
        final target = _findAlarm(store, args);
        await alarms.setEnabled(target, enabled);
        return jsonEncode({
          'ok': true,
          'id': target.id,
          'time': target.timeLabel,
          'enabled': enabled,
        });
      },
    ),
  ];
}

/// 按 id 或 time 定位唯一闹钟；找不到/有歧义抛 [FormatException]。
AlarmRecord _findAlarm(AppStore store, Map<String, dynamic> args) {
  final id = (args['id'] as String? ?? '').trim();
  if (id.isNotEmpty) {
    final target = store.alarmById(id);
    if (target == null) throw FormatException('找不到 id 为 $id 的闹钟');
    return target;
  }
  final timeRaw = (args['time'] as String? ?? '').trim();
  if (timeRaw.isEmpty) throw const FormatException('需要 id 或 time 之一');
  final t = tryParseClockTime(timeRaw);
  if (t == null) {
    throw FormatException('time「$timeRaw」无法识别。可选：07:30 / 7点半 / 晚上9点15');
  }
  final matches = store.alarms
      .where((a) => a.hour == t.hour && a.minute == t.minute)
      .toList();
  if (matches.isEmpty) {
    throw FormatException(
        '找不到 ${t.hour}:${t.minute.toString().padLeft(2, '0')} 的闹钟');
  }
  if (matches.length > 1) {
    throw FormatException('该时间有 ${matches.length} 个闹钟，请改用 id 指定：'
        '${matches.map((e) => e.id).join(', ')}');
  }
  return matches.first;
}

String _repeatLabel(AlarmRecord record) {
  if (record.isOneShot) {
    return DateFormat('yyyy-MM-dd').format(record.date!);
  }
  if (record.isDaily) return '每天';
  const names = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '每周${record.daysOfWeek.map((d) => names[d]).join('、')}';
}
