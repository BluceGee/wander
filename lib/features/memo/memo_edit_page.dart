import 'package:flutter/material.dart';

import '../../core/models/memo.dart';
import '../../core/storage/app_store.dart';

/// 新建 / 编辑备忘录。
class MemoEditPage extends StatefulWidget {
  const MemoEditPage({super.key, required this.store, this.memo});

  final AppStore store;

  /// 为空表示新建。
  final Memo? memo;

  @override
  State<MemoEditPage> createState() => _MemoEditPageState();
}

class _MemoEditPageState extends State<MemoEditPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  bool _dirty = false;

  bool get _isEditing => widget.memo != null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.memo?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.memo?.content ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内容为空，未保存')),
      );
      return;
    }

    if (_isEditing) {
      await widget.store.updateMemo(
        widget.memo!.copyWith(title: title, content: content),
      );
    } else {
      await widget.store.addMemo(Memo.create(title: title, content: content));
    }
    if (mounted) {
      _dirty = false;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_dirty) {
          Navigator.of(context).pop();
          return;
        }
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('放弃未保存的修改？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('继续编辑'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('放弃'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? '编辑备忘录' : '新建备忘录'),
          actions: [
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('保存'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _titleCtrl,
                autofocus: !_isEditing,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
                decoration: const InputDecoration(hintText: '标题'),
                onChanged: (_) => setState(() => _dirty = true),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _contentCtrl,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '写点什么……',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
