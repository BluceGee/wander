import 'package:flutter/material.dart';

import '../../core/models/expense.dart';
import '../../core/storage/app_store.dart';
import '../../core/utils/format.dart';
import '../expense/expense_page.dart';
import '../games/games_hub_page.dart';
import '../memo/memo_list_page.dart';
import '../settings/settings_page.dart';

/// 工具页：功能入口网格 + 快速统计（从对话主页的菜单进入）。
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('全部功能'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '设置',
                onPressed: () => _open(context, SettingsPage(store: store)),
              ),
            ],
          ),
          SliverToBoxAdapter(child: _QuickStats(store: store)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                _FeatureCard(
                  icon: Icons.note_alt_outlined,
                  color: scheme.secondary,
                  title: '备忘录',
                  subtitle: '随手记，随时查',
                  onTap: () => _open(context, MemoListPage(store: store)),
                ),
                _FeatureCard(
                  icon: Icons.account_balance_wallet_outlined,
                  color: scheme.tertiary,
                  title: '记账',
                  subtitle: '收支一目了然',
                  onTap: () => _open(context, ExpensePage(store: store)),
                ),
                _FeatureCard(
                  icon: Icons.sports_esports_outlined,
                  color: scheme.error,
                  title: '小游戏',
                  subtitle: '休闲放松一下',
                  onTap: () => _open(context, GamesHubPage()),
                ),
                _FeatureCard(
                  icon: Icons.settings_outlined,
                  color: scheme.secondary,
                  title: '设置',
                  subtitle: '外观、账号与数据',
                  onTap: () => _open(context, SettingsPage(store: store)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final summary = ExpenseSummary.of(store.expensesOfMonth(DateTime.now()));
        final theme = Theme.of(context);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      label: '本月支出',
                      value: formatMoney(summary.totalExpense),
                      color: theme.colorScheme.error,
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      label: '本月收入',
                      value: formatMoney(summary.totalIncome),
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      label: '备忘录',
                      value: '${store.memos.length}',
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
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
              .titleLarge
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color),
              ),
              const Spacer(),
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
