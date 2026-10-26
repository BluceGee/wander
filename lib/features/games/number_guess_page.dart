import 'dart:math';

import 'package:flutter/material.dart';

/// 猜数字：系统随机生成 1~100 的数，按提示猜出答案。
class NumberGuessPage extends StatefulWidget {
  const NumberGuessPage({super.key});

  @override
  State<NumberGuessPage> createState() => _NumberGuessPageState();
}

class _NumberGuessPageState extends State<NumberGuessPage> {
  final _rng = Random();
  final _ctrl = TextEditingController();

  late int _answer;
  int _attempts = 0;
  int _best = 0;
  bool _won = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _answer = _rng.nextInt(100) + 1;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _guess() {
    if (_won) return;
    final value = int.tryParse(_ctrl.text.trim());
    if (value == null || value < 1 || value > 100) {
      setState(() => _hint = '请输入 1 ~ 100 之间的整数');
      return;
    }
    setState(() {
      _attempts++;
      if (value == _answer) {
        _won = true;
        _hint = '猜对了！答案就是 $_answer';
        _best = _best == 0 ? _attempts : min(_best, _attempts);
      } else {
        final diff = (value - _answer).abs();
        final direction = value < _answer ? '大了' : '小了';
        final closeness = diff <= 5
            ? '非常接近'
            : diff <= 15
                ? '有点接近'
                : '差得远';
        _hint = '$value $direction，$closeness';
      }
      _ctrl.clear();
    });
  }

  void _reset() {
    setState(() {
      _answer = _rng.nextInt(100) + 1;
      _attempts = 0;
      _won = false;
      _hint = null;
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('猜数字'),
        actions: [
          IconButton(
            tooltip: '换一个数',
            icon: const Icon(Icons.refresh),
            onPressed: _reset,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(
              '我心里想了一个 1~100 的数',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _won
                  ? '你用了 $_attempts 次猜中${_best > 0 ? '（最佳 $_best 次）' : ''}'
                  : '已经猜了 $_attempts 次',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            if (_won)
              Text('🎉', textAlign: TextAlign.center, style: theme.textTheme.displayLarge)
            else
              TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                decoration: const InputDecoration(hintText: '?'),
                onSubmitted: (_) => _guess(),
              ),
            const SizedBox(height: 16),
            if (_hint != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _won
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _hint!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _won ? _reset : _guess,
              icon: Icon(_won ? Icons.replay : Icons.send),
              label: Text(_won ? '再来一局' : '猜一下'),
            ),
          ],
        ),
      ),
    );
  }
}
