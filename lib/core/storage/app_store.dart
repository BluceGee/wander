import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../agent/llm_client.dart';
import '../models/expense.dart';
import '../models/memo.dart';

/// 全局应用状态：备忘录、账单、外观设置。
///
/// 数据以 JSON 形式保存在 [SharedPreferences] 中，
/// 界面通过 [ListenableBuilder] 监听本对象自动刷新。
class AppStore extends ChangeNotifier {
  AppStore(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  static const _kMemos = 'memos';
  static const _kExpenses = 'expenses';
  static const _kThemeMode = 'themeMode';
  static const _kLlmBaseUrl = 'llmBaseUrl';
  static const _kLlmApiKey = 'llmApiKey';
  static const _kLlmModel = 'llmModel';

  List<Memo> _memos = [];
  List<ExpenseRecord> _expenses = [];
  ThemeMode _themeMode = ThemeMode.system;
  LlmConfig _llmConfig = LlmConfig.empty;

  /// 备忘录（置顶优先，其次按更新时间倒序）。
  List<Memo> get memos {
    final list = [..._memos];
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  /// 全部账单（按日期倒序）。
  List<ExpenseRecord> get expenses {
    final list = [..._expenses];
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  ThemeMode get themeMode => _themeMode;

  /// AI 助手的 LLM 接入配置（OpenAI 兼容，如 MiMo 平台）。
  LlmConfig get llmConfig => _llmConfig;

  Future<void> setLlmConfig({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    _llmConfig = LlmConfig(
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      model: model.trim(),
    );
    await _prefs.setString(_kLlmBaseUrl, _llmConfig.baseUrl);
    await _prefs.setString(_kLlmApiKey, _llmConfig.apiKey);
    await _prefs.setString(_kLlmModel, _llmConfig.model);
    notifyListeners();
  }

  /// 读取指定月份的账单（默认本月）。
  List<ExpenseRecord> expensesOfMonth(DateTime month) {
    return expenses
        .where((e) => e.date.year == month.year && e.date.month == month.month)
        .toList();
  }

  void _load() {
    final memosJson = _prefs.getString(_kMemos);
    if (memosJson != null) {
      _memos = (jsonDecode(memosJson) as List)
          .map((e) => Memo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final expensesJson = _prefs.getString(_kExpenses);
    if (expensesJson != null) {
      _expenses = (jsonDecode(expensesJson) as List)
          .map((e) => ExpenseRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final mode = _prefs.getString(_kThemeMode);
    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == mode,
      orElse: () => ThemeMode.system,
    );
    _llmConfig = LlmConfig(
      baseUrl: _prefs.getString(_kLlmBaseUrl) ?? '',
      apiKey: _prefs.getString(_kLlmApiKey) ?? '',
      model: _prefs.getString(_kLlmModel) ?? '',
    );
  }

  Future<void> _persistMemos() =>
      _prefs.setString(_kMemos, jsonEncode(_memos.map((e) => e.toJson()).toList()));

  Future<void> _persistExpenses() => _prefs.setString(
      _kExpenses, jsonEncode(_expenses.map((e) => e.toJson()).toList()));

  // ---------- 备忘录 ----------

  Future<void> addMemo(Memo memo) async {
    _memos = [..._memos, memo];
    await _persistMemos();
    notifyListeners();
  }

  Future<void> updateMemo(Memo memo) async {
    _memos = [
      for (final m in _memos)
        if (m.id == memo.id) memo else m,
    ];
    await _persistMemos();
    notifyListeners();
  }

  Future<void> deleteMemo(String id) async {
    _memos = _memos.where((m) => m.id != id).toList();
    await _persistMemos();
    notifyListeners();
  }

  Future<void> togglePinned(Memo memo) async {
    await updateMemo(memo.copyWith(pinned: !memo.pinned));
  }

  // ---------- 账单 ----------

  Future<void> addExpense(ExpenseRecord record) async {
    _expenses = [..._expenses, record];
    await _persistExpenses();
    notifyListeners();
  }

  Future<void> deleteExpense(String id) async {
    _expenses = _expenses.where((e) => e.id != id).toList();
    await _persistExpenses();
    notifyListeners();
  }

  // ---------- 设置 ----------

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  /// 清空全部数据（设置页里使用，需二次确认）。
  Future<void> clearAll() async {
    _memos = [];
    _expenses = [];
    await _persistMemos();
    await _persistExpenses();
    notifyListeners();
  }
}
