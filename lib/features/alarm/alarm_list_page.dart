import 'package:flutter/material.dart';

import '../../core/alarm/alarm_service.dart';
import '../../core/models/alarm.dart';
import 'alarm_edit_page.dart';

/// 闹钟列表：开关、编辑、删除、新建。
class AlarmListPage extends StatelessWidget {
  const AlarmListPage({super.key, required this.alarms});

  final AlarmService alarms;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('闹钟')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新建'),
        onPressed: () => _edit(context, null),
      ),
      body: ListenableBuilder(
        listenable: alarms.store,
        builder: (context, _) {
          final records = alarms.store.alarms;
          if (records.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _AlarmTile(
              record: records[index],
              alarms: alarms,
              onTap: () => _edit(context, records[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, AlarmRecord? record) {
    return Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => AlarmEditPage(alarms: alarms, record: record)),
    );
  }
}

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({
    required this.record,
    required this.alarms,
    required this.onTap,
  });

  final AlarmRecord record;
  final AlarmService alarms;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = !record.enabled;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _confirmDelete(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.timeLabel,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: muted ? theme.colorScheme.outline : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (record.label.isNotEmpty) record.label,
                        _repeatText(record),
                        '${record.dismissMethod.label}关闭',
                        if (record.snoozeEnabled)
                          '贪睡${record.snoozeMinutes}分钟×${record.snoozeLimit}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted
                            ? theme.colorScheme.outline
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: record.enabled,
                onChanged: (v) => alarms.setEnabled(record, v),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除',
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _repeatText(AlarmRecord r) {
    if (r.isOneShot) {
      final d = r.date!;
      return '一次性 ${d.month}月${d.day}日';
    }
    if (r.isDaily) return '每天';
    const names = ['', '一', '二', '三', '四', '五', '六', '日'];
    return '每周${r.daysOfWeek.map((d) => names[d]).join('、')}';
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除闹钟？'),
        content: Text('「${record.timeLabel}${record.label.isEmpty ? '' : ' ${record.label}'}」将被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await alarms.remove(record.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alarm_off_outlined,
              size: 72, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text('还没有闹钟', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('点右下角「新建」，或直接对 AI 助手说「明早 7 点叫我」',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
