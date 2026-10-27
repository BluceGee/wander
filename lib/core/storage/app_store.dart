import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../agent/llm_client.dart';
import '../models/alarm.dart';
import '../models/expense.dart';
import '../models/memo.dart';
import 'key_vault.dart';

/// 全局应用状态：备忘录、账单、闹钟、外观设置、LLM 接入配置。
///
/// 一般数据以 JSON 形式保存在 [SharedPreferences] 中；
/// API Key 单独存放于 [KeyVault]（Android Keystore 加密），
/// 不落明文 SharedPreferences。界面通过 [ListenableBuilder] 监听刷新。
class AppStore extends ChangeNotifier {
  AppStore._(this._prefs, this._vault);

  /// 加载持久化状态；API Key 若存有旧版明文会迁入 [KeyVault] 并清除。
  static Future<AppStore> create(
    SharedPreferences prefs, {
    KeyVault? vault,
  }) async {
    final store = AppStore._(prefs, vault ?? const FlutterKeyVault());
    await store._load();
    return store;
  }

  final SharedPreferences _prefs;
  final KeyVault _vault;

  static const _kMemos = 'memos';
  static const _kExpenses = 'expenses';
  static const _kAlarms = 'alarms';
  static const _kThemeMode = 'themeMode';
  static const _kLlmBaseUrl = 'llmBaseUrl';
  static const _kLlmModel = 'llmModel';

  /// 旧版明文键（1.0.0 及以前）：只为迁移而读，读到即删。
  static const _kLegacyLlmApiKey = 'llmApiKey';

  /// KeyVault 中 API Key / 登录令牌的键名。
  static const _kVaultApiKey = 'llm_api_key';
  static const _kVaultAuthToken = 'auth_token';

  static const _kAuthUsername = 'authUsername';
  static const _kAuthCreatedAt = 'authCreatedAt';
  static const _kWelcomeDone = 'welcomeDone';

  List<Memo> _memos = [];
  List<ExpenseRecord> _expenses = [];
  List<AlarmRecord> _alarms = [];
  ThemeMode _themeMode = ThemeMode.system;
  LlmConfig _llmConfig = LlmConfig.empty;

  String _authToken = '';
  String _authUsername = '';
  String _authCreatedAt = '';
  bool _welcomeDone = false;

  /// 登录令牌（存 KeyVault，不落明文）。
  String get authToken => _authToken;

  bool get isLoggedIn => _authToken.isNotEmpty;

  String get authUsername => _authUsername;

  String get authCreatedAt => _authCreatedAt;

  /// 欢迎/登录引导是否已完成（登录或跳过都算；登录非强制）。
  bool get welcomeDone => _welcomeDone;

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

  /// 全部闹钟（按时间先后排序，同刻按 id）。
  List<AlarmRecord> get alarms {
    final list = [..._alarms];
    list.sort((a, b) {
      final c = a.hour.compareTo(b.hour);
      if (c != 0) return c;
      final m = a.minute.compareTo(b.minute);
      if (m != 0) return m;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  AlarmRecord? alarmById(String id) {
    for (final a in _alarms) {
      if (a.id == id) return a;
    }
    return null;
  }

  ThemeMode get themeMode => _themeMode;

  /// AI 助手的 LLM 接入配置（Anthropic 兼容，如 Claude API）。
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
    await _prefs.setString(_kLlmModel, _llmConfig.model);
    if (_llmConfig.apiKey.isEmpty) {
      await _vault.delete(_kVaultApiKey);
    } else {
      await _vault.write(_kVaultApiKey, _llmConfig.apiKey);
    }
    // 防御：任何情况下都不让 API Key 落回明文 SharedPreferences
    await _prefs.remove(_kLegacyLlmApiKey);
    notifyListeners();
  }

  /// 读取指定月份的账单（默认本月）。
  List<ExpenseRecord> expensesOfMonth(DateTime month) {
    return expenses
        .where((e) => e.date.year == month.year && e.date.month == month.month)
        .toList();
  }

  Future<void> _load() async {
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
    final alarmsJson = _prefs.getString(_kAlarms);
    if (alarmsJson != null) {
      _alarms = (jsonDecode(alarmsJson) as List)
          .map((e) => AlarmRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final mode = _prefs.getString(_kThemeMode);
    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == mode,
      orElse: () => ThemeMode.system,
    );

    // API Key：优先 KeyVault；若只有旧版明文（1.0.0），迁入 KeyVault 后删除明文
    var apiKey = await _vault.read(_kVaultApiKey) ?? '';
    final legacyKey = _prefs.getString(_kLegacyLlmApiKey);
    if (legacyKey != null) {
      if (apiKey.isEmpty && legacyKey.isNotEmpty) {
        apiKey = legacyKey;
        await _vault.write(_kVaultApiKey, legacyKey);
      }
      await _prefs.remove(_kLegacyLlmApiKey);
    }

    _llmConfig = LlmConfig(
      baseUrl: _prefs.getString(_kLlmBaseUrl) ?? '',
      apiKey: apiKey,
      model: _prefs.getString(_kLlmModel) ?? '',
    );

    _authToken = await _vault.read(_kVaultAuthToken) ?? '';
    _authUsername = _prefs.getString(_kAuthUsername) ?? '';
    _authCreatedAt = _prefs.getString(_kAuthCreatedAt) ?? '';
    _welcomeDone = _prefs.getBool(_kWelcomeDone) ?? false;
  }

  // ---------- 账号会话 ----------

  /// 完成欢迎引导（登录或跳过都调用）。
  Future<void> completeWelcome() async {
    _welcomeDone = true;
    await _prefs.setBool(_kWelcomeDone, true);
    notifyListeners();
  }

  /// 保存登录会话：令牌进 KeyVault，用户信息进 prefs。
  Future<void> saveSession({
    required String token,
    required String username,
    required String createdAt,
  }) async {
    await _vault.write(_kVaultAuthToken, token);
    await _prefs.setString(_kAuthUsername, username);
    await _prefs.setString(_kAuthCreatedAt, createdAt);
    _authToken = token;
    _authUsername = username;
    _authCreatedAt = createdAt;
    notifyListeners();
  }

  /// 清除本地会话（退出登录）。
  Future<void> clearSession() async {
    await _vault.delete(_kVaultAuthToken);
    await _prefs.remove(_kAuthUsername);
    await _prefs.remove(_kAuthCreatedAt);
    _authToken = '';
    _authUsername = '';
    _authCreatedAt = '';
    notifyListeners();
  }

  Future<void> _persistMemos() =>
      _prefs.setString(_kMemos, jsonEncode(_memos.map((e) => e.toJson()).toList()));

  Future<void> _persistExpenses() => _prefs.setString(
      _kExpenses, jsonEncode(_expenses.map((e) => e.toJson()).toList()));

  Future<void> _persistAlarms() =>
      _prefs.setString(_kAlarms, jsonEncode(_alarms.map((e) => e.toJson()).toList()));

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

  // ---------- 闹钟 ----------

  Future<void> addAlarm(AlarmRecord record) async {
    _alarms = [..._alarms, record];
    await _persistAlarms();
    notifyListeners();
  }

  Future<void> updateAlarm(AlarmRecord record) async {
    _alarms = [
      for (final a in _alarms)
        if (a.id == record.id) record else a,
    ];
    await _persistAlarms();
    notifyListeners();
  }

  Future<void> deleteAlarm(String id) async {
    _alarms = _alarms.where((a) => a.id != id).toList();
    await _persistAlarms();
    notifyListeners();
  }

  // ---------- 设置 ----------

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  /// 清空全部数据（设置页里使用，需二次确认）。
  ///
  /// 注意：闹钟的原生调度不在这里撤销，调用方（设置页）应同时
  /// 调用 AlarmService 的清理，避免留下无记录的孤儿闹钟。
  Future<void> clearAll() async {
    _memos = [];
    _expenses = [];
    _alarms = [];
    await _persistMemos();
    await _persistExpenses();
    await _persistAlarms();
    notifyListeners();
  }
}
