import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/expense.dart';
import '../../core/storage/app_store.dart';
import '../../core/utils/format.dart';

/// 记一笔：支出 / 收入录入表单。
class ExpenseEditPage extends StatefulWidget {
  const ExpenseEditPage({super.key, required this.store});

  final AppStore store;

  @override
  State<ExpenseEditPage> createState() => _ExpenseEditPageState();
}

class _ExpenseEditPageState extends State<ExpenseEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _isExpense = true;
  String _category = ExpenseCategory.expenseCategories.first.name;
  DateTime _date = DateTime.now();

  List<ExpenseCategory> get _categories => _isExpense
      ? ExpenseCategory.expenseCategories
      : ExpenseCategory.incomeCategories;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _toggleType(bool isExpense) {
    setState(() {
      _isExpense = isExpense;
      _category = _categories.first.name;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountCtrl.text.trim());
    await widget.store.addExpense(
      ExpenseRecord.create(
        amount: amount,
        isExpense: _isExpense,
        category: _category,
        note: _noteCtrl.text.trim(),
        date: _date,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记一笔')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('支出'), icon: Icon(Icons.arrow_upward)),
                ButtonSegment(value: false, label: Text('收入'), icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_isExpense},
              onSelectionChanged: (s) => _toggleType(s.first),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                hintText: '0.00',
                prefixText: '¥ ',
              ),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return '请输入大于 0 的金额';
                return null;
              },
            ),
            const SizedBox(height: 20),
            Text('分类', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _categories)
                  ChoiceChip(
                    label: Text('${c.icon} ${c.name}'),
                    selected: _category == c.name,
                    onSelected: (_) => setState(() => _category = c.name),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('日期'),
              trailing: Text(formatDate(_date),
                  style: Theme.of(context).textTheme.titleSmall),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                hintText: '备注（可选）',
                prefixIcon: Icon(Icons.short_text),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
