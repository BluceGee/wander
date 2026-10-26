import 'package:flutter/material.dart';

import '../../core/models/expense.dart';
import '../../core/storage/app_store.dart';
import '../../core/utils/format.dart';
import 'expense_edit_page.dart';

/// 记账：月度汇总 + 流水列表。
class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key, required this.store});

  final AppStore store;

  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  late DateTime _month = DateTime.now();

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记账')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
        onPressed: () => _openEdit(context),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final records = widget.store.expensesOfMonth(_month);
          final summary = ExpenseSummary.of(records);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _MonthSwitcher(
                month: _month,
                onPrev: () => _shiftMonth(-1),
                onNext: () => _shiftMonth(1),
              ),
              const SizedBox(height: 12),
              _SummaryCard(summary: summary),
              const SizedBox(height: 16),
              if (records.isEmpty)
                const _EmptyState()
              else ...[
                Text('流水', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...records.map(
                  (r) => _RecordTile(
                    record: r,
                    onDelete: () => widget.store.deleteExpense(r.id),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _openEdit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExpenseEditPage(store: widget.store)),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
        Text(
          formatMonth(month),
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _AmountBox(
                    label: '支出',
                    value: formatMoney(summary.totalExpense),
                    color: scheme.error,
                  ),
                ),
                Expanded(
                  child: _AmountBox(
                    label: '收入',
                    value: formatMoney(summary.totalIncome),
                    color: scheme.primary,
                  ),
                ),
                Expanded(
                  child: _AmountBox(
                    label: '结余',
                    value: formatMoney(summary.balance),
                    color: scheme.tertiary,
                  ),
                ),
              ],
            ),
            if (summary.byCategory.isNotEmpty) ...[
              const Divider(height: 24),
              ..._sortedCategories(summary).map(
                (e) => _CategoryBar(
                  name: e.key,
                  amount: e.value,
                  ratio: summary.totalExpense == 0
                      ? 0
                      : e.value / summary.totalExpense,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分类支出按金额从大到小排序。
List<MapEntry<String, double>> _sortedCategories(ExpenseSummary summary) {
  final entries = summary.byCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries;
}

class _AmountBox extends StatelessWidget {
  const _AmountBox({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.name,
    required this.amount,
    required this.ratio,
  });

  final String name;
  final double amount;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: Theme.of(context).textTheme.bodyMedium),
              Text(formatMoney(amount),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.onDelete});

  final ExpenseRecord record;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountColor = record.isExpense ? theme.colorScheme.error : theme.colorScheme.primary;

    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Text(ExpenseCategory.iconOf(record.category)),
          ),
          title: Text(record.category),
          subtitle: Text(
            record.note.isEmpty ? formatDate(record.date) : '${record.note} · ${formatDate(record.date)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            '${record.isExpense ? '-' : '+'}${formatMoney(record.amount)}',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: amountColor, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 72, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text('本月还没有账单', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('点右下角「记一笔」开始记账', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
