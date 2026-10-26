import 'package:flutter/material.dart';

/// 井字棋：玩家执 ○，电脑执 ✕（极小化极大算法，永不失误）。
class TicTacToePage extends StatefulWidget {
  const TicTacToePage({super.key});

  @override
  State<TicTacToePage> createState() => _TicTacToePageState();
}

enum _Cell { empty, player, ai }

class _TicTacToePageState extends State<TicTacToePage> {
  static const _winLines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8], // 行
    [0, 3, 6], [1, 4, 7], [2, 5, 8], // 列
    [0, 4, 8], [2, 4, 6], // 对角
  ];

  List<_Cell> _board = List.filled(9, _Cell.empty);
  bool _playerTurn = true;
  int _playerScore = 0;
  int _aiScore = 0;
  int _draws = 0;

  bool get _gameOver => _winner != null || _isDraw;

  _Cell? get _winner {
    for (final line in _winLines) {
      final a = _board[line[0]];
      if (a != _Cell.empty && a == _board[line[1]] && a == _board[line[2]]) {
        return a;
      }
    }
    return null;
  }

  bool get _isDraw => !_board.contains(_Cell.empty) && _winner == null;

  void _onTap(int index) {
    if (!_playerTurn || _gameOver || _board[index] != _Cell.empty) return;
    setState(() {
      _board[index] = _Cell.player;
      _playerTurn = false;
      _updateScore();
    });
    if (!_gameOver) {
      Future.delayed(const Duration(milliseconds: 280), _aiMove);
    }
  }

  void _updateScore() {
    final w = _winner;
    if (w == _Cell.player) _playerScore++;
    if (w == _Cell.ai) _aiScore++;
    if (_isDraw) _draws++;
  }

  void _aiMove() {
    if (!mounted || _gameOver) return;
    final move = _bestMove();
    if (move == null) return;
    setState(() {
      _board[move] = _Cell.ai;
      _playerTurn = true;
      _updateScore();
    });
  }

  /// 极小化极大：电脑全力争胜，其次求和，最后堵玩家。
  int? _bestMove() {
    int bestScore = -1 << 31;
    int? bestIndex;
    for (int i = 0; i < 9; i++) {
      if (_board[i] != _Cell.empty) continue;
      _board[i] = _Cell.ai;
      final score = _minimax(isMaximizing: false);
      _board[i] = _Cell.empty;
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  int _minimax({required bool isMaximizing, int depth = 0}) {
    final w = _winner;
    if (w == _Cell.ai) return 10 - depth;
    if (w == _Cell.player) return depth - 10;
    if (!_board.contains(_Cell.empty)) return 0;

    if (isMaximizing) {
      int best = -1 << 31;
      for (int i = 0; i < 9; i++) {
        if (_board[i] != _Cell.empty) continue;
        _board[i] = _Cell.ai;
        final v = _minimax(isMaximizing: false, depth: depth + 1);
        if (v > best) best = v;
        _board[i] = _Cell.empty;
      }
      return best;
    } else {
      int best = 1 << 31;
      for (int i = 0; i < 9; i++) {
        if (_board[i] != _Cell.empty) continue;
        _board[i] = _Cell.player;
        final v = _minimax(isMaximizing: true, depth: depth + 1);
        if (v < best) best = v;
        _board[i] = _Cell.empty;
      }
      return best;
    }
  }

  void _reset({bool keepScore = true}) {
    setState(() {
      _board = List.filled(9, _Cell.empty);
      _playerTurn = true;
      if (!keepScore) {
        _playerScore = 0;
        _aiScore = 0;
        _draws = 0;
      }
    });
  }

  String get _status {
    final w = _winner;
    if (w == _Cell.player) return '你赢了！🎉';
    if (w == _Cell.ai) return '电脑获胜 🤖';
    if (_isDraw) return '平局 🤝';
    return _playerTurn ? '轮到你了' : '电脑思考中…';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context).shortestSide.clamp(240.0, 420.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('井字棋'),
        actions: [
          IconButton(
            tooltip: '重新计分',
            icon: const Icon(Icons.refresh),
            onPressed: () => _reset(keepScore: false),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ScoreChip(label: '你', value: _playerScore, color: theme.colorScheme.primary),
                  _ScoreChip(label: '平', value: _draws, color: theme.colorScheme.outline),
                  _ScoreChip(label: '电脑', value: _aiScore, color: theme.colorScheme.error),
                ],
              ),
              const SizedBox(height: 20),
              Text(_status, style: theme.textTheme.titleLarge),
              const SizedBox(height: 20),
              SizedBox(
                width: size,
                height: size,
                child: GridView.count(
                  crossAxisCount: 3,
                  physics: const NeverScrollableScrollPhysics(),
                  children: List.generate(9, (i) => _CellView(
                    cell: _board[i],
                    isWin: _winner != null &&
                        _winLines.any((l) => l.contains(i) &&
                            _board[l[0]] == _winner &&
                            _board[l[1]] == _winner &&
                            _board[l[2]] == _winner),
                    onTap: () => _onTap(i),
                  )),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _reset(),
                icon: const Icon(Icons.replay),
                label: const Text('再来一局'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            '$value',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _CellView extends StatelessWidget {
  const _CellView({
    required this.cell,
    required this.isWin,
    required this.onTap,
  });

  final _Cell cell;
  final bool isWin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (cell) {
      _Cell.player => theme.colorScheme.primary,
      _Cell.ai => theme.colorScheme.error,
      _Cell.empty => theme.colorScheme.onSurfaceVariant,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isWin
              ? color.withValues(alpha: 0.18)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            switch (cell) {
              _Cell.player => '○',
              _Cell.ai => '✕',
              _Cell.empty => '',
            },
            style: theme.textTheme.displayMedium?.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}
