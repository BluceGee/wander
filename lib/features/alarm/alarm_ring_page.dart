import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/alarm/alarm_service.dart';
import '../../core/models/alarm.dart';
import 'math_problems.dart';

/// 全屏响铃页：完成自定义关闭挑战才能停，也可按自定义时长贪睡。
class AlarmRingPage extends StatefulWidget {
  const AlarmRingPage({
    super.key,
    required this.alarms,
    required this.record,
    this.shakeEvents,
  });

  final AlarmService alarms;
  final AlarmRecord record;

  /// 摇一摇数据流（测试注入；缺省用加速度计）。
  final Stream<UserAccelerometerEvent>? shakeEvents;

  @override
  State<AlarmRingPage> createState() => _AlarmRingPageState();
}

class _AlarmRingPageState extends State<AlarmRingPage> {
  bool _closing = false;

  AlarmRecord get record => widget.record;

  bool get canSnooze =>
      record.snoozeEnabled && record.snoozeCount < record.snoozeLimit;

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    await widget.alarms.stopRinging(record);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze() async {
    if (_closing) return;
    final ok = await widget.alarms.snooze(record);
    if (!mounted) return;
    if (ok) {
      _closing = true;
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('贪睡次数已用完，请完成关闭')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Text('闹钟响了', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                record.timeLabel,
                style: theme.textTheme.displayLarge
                    ?.copyWith(fontWeight: FontWeight.w200),
              ),
              if (record.label.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(record.label, style: theme.textTheme.titleLarge),
              ],
              const SizedBox(height: 8),
              Text(
                '完成「${record.dismissMethod.label}」才能关闭',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              _Challenge(
                record: record,
                onDone: _dismiss,
                shakeEvents: widget.shakeEvents,
              ),
              const SizedBox(height: 16),
              if (canSnooze)
            TextButton.icon(
                  onPressed: _snooze,
                  icon: const Icon(Icons.snooze),
                  label: Text(
                      '贪睡 ${record.snoozeMinutes} 分钟（剩 ${record.snoozeLimit - record.snoozeCount} 次）'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 关闭挑战分发。
class _Challenge extends StatelessWidget {
  const _Challenge({
    required this.record,
    required this.onDone,
    this.shakeEvents,
  });

  final AlarmRecord record;
  final VoidCallback onDone;
  final Stream<UserAccelerometerEvent>? shakeEvents;

  @override
  Widget build(BuildContext context) {
    return switch (record.dismissMethod) {
      AlarmDismissMethod.tap => _TapChallenge(onDone: onDone),
      AlarmDismissMethod.hold =>
        _HoldChallenge(seconds: record.holdSeconds, onDone: onDone),
      AlarmDismissMethod.math => _MathChallenge(
          difficulty: record.mathDifficulty,
          count: record.mathQuestions,
          onDone: onDone,
        ),
      AlarmDismissMethod.typing =>
        _TypingChallenge(phrase: record.typePhrase, onDone: onDone),
      AlarmDismissMethod.shake => _ShakeChallenge(
          target: record.shakeCount,
          onDone: onDone,
          events: shakeEvents,
        ),
    };
  }
}

class _TapChallenge extends StatelessWidget {
  const _TapChallenge({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        textStyle: Theme.of(context).textTheme.titleLarge,
      ),
      onPressed: onDone,
      icon: const Icon(Icons.alarm_off),
      label: const Text('关闭'),
    );
  }
}

class _HoldChallenge extends StatefulWidget {
  const _HoldChallenge({required this.seconds, required this.onDone});

  final int seconds;
  final VoidCallback onDone;

  @override
  State<_HoldChallenge> createState() => _HoldChallengeState();
}

class _HoldChallengeState extends State<_HoldChallenge> {
  Timer? _timer;
  double _progress = 0;

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      setState(() => _progress += 0.05 / widget.seconds);
      if (_progress >= 1) {
        _timer?.cancel();
        widget.onDone();
      }
    });
  }

  void _stop() {
    _timer?.cancel();
    setState(() => _progress = 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          _progress <= 0 ? '按住按钮 ${widget.seconds} 秒关闭' : '别松手…',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onLongPressStart: (_) => _start(),
          onLongPressEnd: (_) => _stop(),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              color: theme.colorScheme.primaryContainer,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: _progress.clamp(0, 1),
                  child: Container(color: theme.colorScheme.primary),
                ),
                Center(
                  child: Text(
                    '长按',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MathChallenge extends StatefulWidget {
  const _MathChallenge({
    required this.difficulty,
    required this.count,
    required this.onDone,
  });

  final AlarmMathDifficulty difficulty;
  final int count;
  final VoidCallback onDone;

  @override
  State<_MathChallenge> createState() => _MathChallengeState();
}

class _MathChallengeState extends State<_MathChallenge> {
  final _ctrl = TextEditingController();
  late MathProblem _problem = generateMathProblem(widget.difficulty);
  int _solved = 0;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final answer = int.tryParse(_ctrl.text.trim());
    if (answer == null || answer != _problem.answer) {
      setState(() {
        _error = '不对，再来一道';
        _problem = generateMathProblem(widget.difficulty);
        _ctrl.clear();
      });
      return;
    }
    final solved = _solved + 1;
    if (solved >= widget.count) {
      widget.onDone();
      return;
    }
    setState(() {
      _solved = solved;
      _error = null;
      _problem = generateMathProblem(widget.difficulty);
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('第 ${_solved + 1} / ${widget.count} 题',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
          '${_problem.expression} = ?',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '答案',
                  errorText: _error,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _submit,
              child: const Text('确定'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TypingChallenge extends StatefulWidget {
  const _TypingChallenge({required this.phrase, required this.onDone});

  final String phrase;
  final VoidCallback onDone;

  @override
  State<_TypingChallenge> createState() => _TypingChallengeState();
}

class _TypingChallengeState extends State<_TypingChallenge> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matched = _ctrl.text.trim() == widget.phrase.trim();
    return Column(
      children: [
        Text('输入下面这句话关闭：', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 8),
        Text('「${widget.phrase}」',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '照着输入'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (matched) widget.onDone();
          },
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: matched ? widget.onDone : null,
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _ShakeChallenge extends StatefulWidget {
  const _ShakeChallenge({
    required this.target,
    required this.onDone,
    this.events,
  });

  final int target;
  final VoidCallback onDone;
  final Stream<UserAccelerometerEvent>? events;

  @override
  State<_ShakeChallenge> createState() => _ShakeChallengeState();
}

class _ShakeChallengeState extends State<_ShakeChallenge> {
  static const _threshold = 2.5;
  static const _debounce = Duration(milliseconds: 300);

  StreamSubscription<UserAccelerometerEvent>? _sub;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  int _count = 0;

  @override
  void initState() {
    super.initState();
    final source = widget.events ?? userAccelerometerEventStream();
    _sub = source.listen((e) {
      final magnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (magnitude < _threshold) return;
      final now = DateTime.now();
      if (now.difference(_last) < _debounce) return;
      _last = now;
      final count = _count + 1;
      if (count >= widget.target) {
        widget.onDone();
        return;
      }
      setState(() => _count = count);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('摇一摇手机 ${widget.target} 次关闭', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 12),
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: _count / widget.target,
                strokeWidth: 8,
              ),
              Center(
                child: Text('$_count / ${widget.target}',
                    style: theme.textTheme.titleLarge),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
