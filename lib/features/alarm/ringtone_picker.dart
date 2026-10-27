import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/alarm.dart';

/// 选中的铃声。
class RingtoneChoice {
  const RingtoneChoice({required this.name, required this.path});

  final String name;

  /// `assets/...` = 内置；绝对路径 = 拷进应用私有目录的副本。
  final String path;
}

/// 铃声原生桥：系统铃声选择、音乐文件选择、试听。
///
/// 原生侧把 content:// 铃声拷贝到 filesDir/ringtones/ 后回传绝对路径
/// （alarm 内核只认 assets 路径与本地文件路径）。
class RingtoneBridge {
  static const channel = MethodChannel('com.xnl.xnl/ringtone');

  /// 系统铃声选择器；用户取消返回 null。
  static Future<RingtoneChoice?> pickSystemRingtone() =>
      _pick('pickRingtone', '系统铃声');

  /// 本地音乐文件选择（SAF）；用户取消返回 null。
  static Future<RingtoneChoice?> pickAudioFile() =>
      _pick('pickAudioFile', '本地音乐');

  static Future<RingtoneChoice?> _pick(String method, String fallbackName) async {
    final result = await channel.invokeMapMethod<String, dynamic>(method);
    if (result == null) return null;
    final path = result['path'] as String?;
    if (path == null || path.isEmpty) return null;
    return RingtoneChoice(
      name: (result['name'] as String?)?.trim().isNotEmpty == true
          ? result['name'] as String
          : fallbackName,
      path: path,
    );
  }

  /// 试听（assets/... 或绝对路径）。
  static Future<void> preview(String path) =>
      channel.invokeMethod<void>('preview', path);

  static Future<void> stopPreview() => channel.invokeMethod<void>('stopPreview');
}

/// 弹出铃声选择对话框。返回选中的铃声；取消返回 null。
Future<RingtoneChoice?> showRingtonePicker(
  BuildContext context, {
  required RingtoneChoice current,
}) {
  return showDialog<RingtoneChoice>(
    context: context,
    builder: (context) => _RingtonePickerDialog(current: current),
  );
}

class _RingtonePickerDialog extends StatefulWidget {
  const _RingtonePickerDialog({required this.current});

  final RingtoneChoice current;

  @override
  State<_RingtonePickerDialog> createState() => _RingtonePickerDialogState();
}

class _RingtonePickerDialogState extends State<_RingtonePickerDialog> {
  late RingtoneChoice _selected = widget.current;

  @override
  void dispose() {
    // 离开即停试听，避免铃声继续响
    RingtoneBridge.stopPreview().ignore();
    super.dispose();
  }

  Future<void> _preview(String path) async {
    try {
      await RingtoneBridge.preview(path);
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('试听不可用')),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('试听需要在真机上使用')),
        );
      }
    }
  }

  Future<void> _pickNative(Future<RingtoneChoice?> Function() pick) async {
    try {
      final choice = await pick();
      if (choice != null && mounted) {
        setState(() => _selected = choice);
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('选择器不可用')),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('选择器需要在真机上使用')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择铃声'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final tone in kBuiltinRingtones)
              ListTile(
                dense: true,
                leading: Icon(
                  _selected.path == tone.assetPath
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(tone.name),
                trailing: IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: '试听',
                  onPressed: () => _preview(tone.assetPath),
                ),
                onTap: () {
                  setState(() {
                    _selected = RingtoneChoice(
                        name: tone.name, path: tone.assetPath);
                  });
                },
              ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.music_note),
              title: const Text('系统铃声…'),
              onTap: () => _pickNative(RingtoneBridge.pickSystemRingtone),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.folder_open),
              title: const Text('本地音乐…'),
              onTap: () => _pickNative(RingtoneBridge.pickAudioFile),
            ),
            if (_selected.path.startsWith('/'))
              ListTile(
                dense: true,
                leading: const Icon(Icons.audiotrack),
                title: Text(_selected.name, overflow: TextOverflow.ellipsis),
                subtitle: const Text('当前自定义铃声'),
                trailing: IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: '试听',
                  onPressed: () => _preview(_selected.path),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
