import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/app_store.dart';

/// 登录 / 注册页。登录非强制——[showSkip] 时显示「跳过」直接进 APP。
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.store,
    this.showSkip = true,
    this.apiClient,
  });

  final AppStore store;

  /// 是否显示「跳过」（首启引导显示；从设置进入时不显示）。
  final bool showSkip;

  /// 测试注入用；默认直连服务器。
  final ApiClient? apiClient;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isRegister = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _skip() async {
    await widget.store.completeWelcome();
  }

  Future<void> _submit() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    setState(() => _error = null);

    if (!RegExp(r'^[\w-]{2,24}$').hasMatch(username)) {
      setState(() => _error = '用户名需为 2-24 位字母、数字、下划线或连字符');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = '密码至少 8 位');
      return;
    }
    if (_isRegister && password != _confirmCtrl.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }

    setState(() => _busy = true);
    try {
      final session = _isRegister
          ? await _api.register(username, password)
          : await _api.login(username, password);
      await widget.store.saveSession(
        token: session.token,
        username: session.user.username,
        createdAt: session.user.createdAt,
      );
      await widget.store.completeWelcome();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '登录失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: widget.showSkip
          ? AppBar(actions: [
              TextButton(
                onPressed: _busy ? null : _skip,
                child: const Text('跳过'),
              ),
            ])
          : AppBar(title: const Text('登录')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.smart_toy_outlined,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'XNL 工具箱',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _isRegister ? '注册一个账号' : '登录后可识别你的身份',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _usernameCtrl,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    hintText: '2-24 位字母、数字、下划线',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  enabled: !_busy,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: '至少 8 位',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_isRegister) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmCtrl,
                    enabled: !_busy,
                    obscureText: _obscure,
                    decoration: const InputDecoration(labelText: '确认密码'),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isRegister ? '注册' : '登录'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _isRegister = !_isRegister;
                            _error = null;
                          }),
                  child: Text(_isRegister ? '已有账号？去登录' : '没有账号？去注册'),
                ),
                if (widget.showSkip)
                  TextButton(
                    onPressed: _busy ? null : _skip,
                    child: const Text('暂不登录，先逛逛'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
