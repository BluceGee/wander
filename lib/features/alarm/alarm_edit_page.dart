import 'package:flutter/material.dart';

import '../../core/alarm/alarm_service.dart';
import '../../core/models/alarm.dart';
import 'ringtone_picker.dart';

/// 新建 / 编辑闹钟：自定义时间、重复、铃声、关闭方式、贪睡。
class AlarmEditPage extends StatefulWidget {
  const AlarmEditPage({
    super.key,
    required this.alarms,
    this.record,
  });

  final AlarmService alarms;

  /// 非空表示编辑。
  final AlarmRecord? record;

  @override
  State<AlarmEditPage> createState() => _AlarmEditPageState();
}

enum _RepeatMode { daily, weekly, once }

class _AlarmEditPageState extends State<AlarmEditPage> {
  late TimeOfDay _time;
  late _RepeatMode _mode;
  late Set<int> _days;
  late DateTime? _date;
  late final TextEditingController _labelCtrl;
  late RingtoneChoice _ringtone;
  late AlarmDismissMethod _dismiss;
  late AlarmMathDifficulty _mathDifficulty;
  late int _mathQuestions;
  late int _holdSeconds;
  late final TextEditingController _phraseCtrl;
  late int _shakeCount;
  late bool _vibrate;
  late bool _snoozeEnabled;
  late int _snoozeMinutes;
  late int _snoozeLimit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _time = TimeOfDay(hour: r?.hour ?? 7, minute: r?.minute ?? 0);
    if (r == null) {
      _mode = _RepeatMode.daily;
    } else if (r.isOneShot) {
      _mode = _RepeatMode.once;
    } else if (r.isWeekly) {
      _mode = _RepeatMode.weekly;
    } else {
      _mode = _RepeatMode.daily;
    }
    _days = {...?r?.daysOfWeek};
    _date = r?.date;
    _labelCtrl = TextEditingController(text: r?.label ?? '');
    _ringtone = RingtoneChoice(
        name: r?.ringtoneName ?? kDefaultRingtoneName,
        path: r?.ringtonePath ?? kDefaultRingtonePath);
    _dismiss = r?.dismissMethod ?? AlarmDismissMethod.tap;
    _mathDifficulty = r?.mathDifficulty ?? AlarmMathDifficulty.easy;
    _mathQuestions = r?.mathQuestions ?? 2;
    _holdSeconds = r?.holdSeconds ?? 3;
    _phraseCtrl = TextEditingController(text: r?.typePhrase ?? '起床啦');
    _shakeCount = r?.shakeCount ?? 10;
    _vibrate = r?.vibrate ?? true;
    _snoozeEnabled = r?.snoozeEnabled ?? true;
    _snoozeMinutes = r?.snoozeMinutes ?? 9;
    _snoozeLimit = r?.snoozeLimit ?? 3;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _phraseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickRingtone() async {
    final choice = await showRingtonePicker(context, current: _ringtone);
    if (choice != null) setState(() => _ringtone = choice);
  }

  Future<void> _save() async {
    if (_saving) return;

    DateTime? date;
    var days = const <int>[];
    switch (_mode) {
      case _RepeatMode.once:
        date = _date ?? DateTime.now();
        final at = DateTime(
            date.year, date.month, date.day, _time.hour, _time.minute);
        if (!at.isAfter(DateTime.now())) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('一次性闹钟的时间已过，请修改时间或日期')),
          );
          return;
        }
      case _RepeatMode.weekly:
        if (_days.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请至少选一个重复日')),
          );
          return;
        }
        days = (_days.toList()..sort());
      case _RepeatMode.daily:
        break;
    }

    setState(() => _saving = true);
    final base = widget.record;
    final record = (base == null
            ? AlarmRecord.create(hour: _time.hour, minute: _time.minute)
            : base.copyWith(
                hour: _time.hour,
                minute: _time.minute,
              ))
        .copyWith(
      label: _labelCtrl.text.trim(),
      date: date,
      daysOfWeek: days,
      ringtonePath: _ringtone.path,
      ringtoneName: _ringtone.name,
      dismissMethod: _dismiss,
      mathDifficulty: _mathDifficulty,
      mathQuestions: _mathQuestions,
      holdSeconds: _holdSeconds,
      typePhrase: _phraseCtrl.text.trim().isEmpty ? '起床啦' : _phraseCtrl.text.trim(),
      shakeCount: _shakeCount,
      vibrate: _vibrate,
      snoozeEnabled: _snoozeEnabled,
      snoozeMinutes: _snoozeMinutes,
      snoozeLimit: _snoozeLimit,
      enabled: true,
    );
    await widget.alarms.save(record);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.record == null ? '新建闹钟' : '编辑闹钟'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // 时间
          Center(
            child: TextButton(
              onPressed: _pickTime,
              child: Text(
                '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                style: theme.textTheme.displayMedium
                    ?.copyWith(fontWeight: FontWeight.w300),
              ),
            ),
          ),
          Center(
            child: TextButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: const Text('点这里改时间'),
            ),
          ),
          const SizedBox(height: 8),

          // 重复
          _Section(title: '重复', children: [
            SegmentedButton<_RepeatMode>(
              segments: const [
                ButtonSegment(value: _RepeatMode.daily, label: Text('每天')),
                ButtonSegment(value: _RepeatMode.weekly, label: Text('每周')),
                ButtonSegment(value: _RepeatMode.once, label: Text('指定日期')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            if (_mode == _RepeatMode.weekly)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final d in const [1, 2, 3, 4, 5, 6, 7])
                      FilterChip(
                        label: Text(
                            const ['', '一', '二', '三', '四', '五', '六', '日'][d]),
                        selected: _days.contains(d),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _days.add(d);
                          } else {
                            _days.remove(d);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            if (_mode == _RepeatMode.once)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(
                  _date == null
                      ? '选择日期'
                      : '${_date!.year}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDate,
              ),
          ]),

          // 备注
          _Section(title: '备注', children: [
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                hintText: '给闹钟起个名字，如「晨跑」（可空）',
              ),
              maxLength: 20,
            ),
          ]),

          // 铃声
          _Section(title: '铃声', children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note),
              title: Text(_ringtone.name),
              subtitle: const Text('内置铃声、系统铃声或本地音乐'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickRingtone,
            ),
          ]),

          // 关闭方式
          _Section(title: '怎么关闭（响铃时要完成才能关）', children: [
            DropdownButtonFormField<AlarmDismissMethod>(
              initialValue: _dismiss,
              decoration: const InputDecoration(labelText: '关闭方式'),
              items: [
                for (final m in AlarmDismissMethod.values)
                  DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (m) => setState(() => _dismiss = m!),
            ),
            if (_dismiss == AlarmDismissMethod.hold) ...[
              const SizedBox(height: 8),
              _SliderRow(
                label: '长按秒数',
                value: _holdSeconds.toDouble(),
                min: 1,
                max: 15,
                divisions: 14,
                labelBuilder: (v) => '${v.round()} 秒',
                onChanged: (v) => setState(() => _holdSeconds = v.round()),
              ),
            ],
            if (_dismiss == AlarmDismissMethod.math) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<AlarmMathDifficulty>(
                initialValue: _mathDifficulty,
                decoration: const InputDecoration(labelText: '题目难度'),
                items: [
                  for (final d in AlarmMathDifficulty.values)
                    DropdownMenuItem(value: d, child: Text(d.label)),
                ],
                onChanged: (d) => setState(() => _mathDifficulty = d!),
              ),
              _SliderRow(
                label: '题目数量',
                value: _mathQuestions.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                labelBuilder: (v) => '${v.round()} 道',
                onChanged: (v) => setState(() => _mathQuestions = v.round()),
              ),
            ],
            if (_dismiss == AlarmDismissMethod.typing) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _phraseCtrl,
                decoration: const InputDecoration(
                  labelText: '要输入的文字',
                  hintText: '如「坚持就是胜利」',
                ),
                maxLength: 30,
              ),
            ],
            if (_dismiss == AlarmDismissMethod.shake) ...[
              const SizedBox(height: 8),
              _SliderRow(
                label: '摇动次数',
                value: _shakeCount.toDouble(),
                min: 5,
                max: 30,
                divisions: 25,
                labelBuilder: (v) => '${v.round()} 次',
                onChanged: (v) => setState(() => _shakeCount = v.round()),
              ),
            ],
          ]),

          // 贪睡
          _Section(title: '贪睡（暂时关闭后多久再响）', children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('允许贪睡'),
              value: _snoozeEnabled,
              onChanged: (v) => setState(() => _snoozeEnabled = v),
            ),
            if (_snoozeEnabled) ...[
              _SliderRow(
                label: '几分钟后再响',
                value: _snoozeMinutes.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                labelBuilder: (v) => '${v.round()} 分钟',
                onChanged: (v) => setState(() => _snoozeMinutes = v.round()),
              ),
              _SliderRow(
                label: '最多贪睡次数',
                value: _snoozeLimit.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                labelBuilder: (v) => '${v.round()} 次',
                onChanged: (v) => setState(() => _snoozeLimit = v.round()),
              ),
            ],
          ]),

          // 其他
          _Section(title: '其他', children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('响铃时振动'),
              value: _vibrate,
              onChanged: (v) => setState(() => _vibrate = v),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelBuilder,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelBuilder;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            Text(
              labelBuilder(value),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: labelBuilder(value),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
