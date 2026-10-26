import 'package:flutter/material.dart';

import '../../core/models/memo.dart';
import '../../core/storage/app_store.dart';
import '../../core/utils/format.dart';
import 'memo_edit_page.dart';

/// 备忘录列表。
class MemoListPage extends StatelessWidget {
  const MemoListPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备忘录')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新建'),
        onPressed: () => _edit(context, null),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final memos = store.memos;
          if (memos.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: memos.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _MemoTile(
              memo: memos[index],
              store: store,
              onTap: () => _edit(context, memos[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, Memo? memo) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemoEditPage(store: store, memo: memo)),
    );
  }
}

class _MemoTile extends StatelessWidget {
  const _MemoTile({
    required this.memo,
    required this.store,
    required this.onTap,
  });

  final Memo memo;
  final AppStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = memo.content.trim().replaceAll(RegExp(r'\s+'), ' ');

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
                    Row(
                      children: [
                        if (memo.pinned) ...[
                          Icon(Icons.push_pin,
                              size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            memo.title.isEmpty ? '（无标题）' : memo.title,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '更新于 ${formatDateTime(memo.updatedAt)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  memo.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: memo.pinned ? theme.colorScheme.primary : null,
                ),
                tooltip: memo.pinned ? '取消置顶' : '置顶',
                onPressed: () => store.togglePinned(memo),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除备忘录？'),
        content: Text('「${memo.title.isEmpty ? '（无标题）' : memo.title}」将被永久删除。'),
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
      await store.deleteMemo(memo.id);
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
          Icon(Icons.note_alt_outlined,
              size: 72, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text('还没有备忘录', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('点右下角「新建」开始记录', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
