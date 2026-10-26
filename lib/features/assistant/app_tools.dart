import 'dart:convert';

import 'package:intl/intl.dart';

import '../../core/agent/agent_tool.dart';
import '../../core/agent/llm_types.dart';
import '../../core/models/expense.dart';
import '../../core/models/memo.dart';
import '../../core/storage/app_store.dart';

/// 框架内置工具集：直接操作 [AppStore] 里的备忘录与账单。
///
/// 返回值统一为 JSON 字符串；抛异常即代表工具失败（会以
/// `is_error` 回传给模型，让它自行纠正参数）。
List<AgentTool> buildAppTools(AppStore store) {
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
              'description': '日期 YYYY-MM-DD，默认今天',
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
          try {
            date = DateFormat('yyyy-MM-dd').parseStrict(dateRaw);
          } on FormatException {
            throw FormatException('date「$dateRaw」格式错误，应为 YYYY-MM-DD');
          }
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
  ];
}
