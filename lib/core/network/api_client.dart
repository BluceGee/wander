import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/account.dart';
import 'pinned_client.dart';
import 'server_config.dart';

/// 后端接口错误（已映射为可读文案）。
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// 账号服务客户端：注册 / 登录 / 登出 / 个人信息。
///
/// 默认直连 [ServerConfig]；测试可注入 [httpClient] 覆盖。
class ApiClient {
  ApiClient({
    String? baseUrl,
    String? certPin,
    http.Client? httpClient,
    this._timeout = const Duration(seconds: 10),
  })  : _base = (baseUrl ?? ServerConfig.baseUrl).replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? _createClient(certPin ?? ServerConfig.certPin);

  final String _base;
  final Duration _timeout;
  final http.Client _http;

  static http.Client _createClient(String certPin) => createPinnedClient(certPin);

  Future<AuthSession> register(String username, String password) async {
    final json = await _postJson('/api/register', {
      'username': username,
      'password': password,
    });
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> login(String username, String password) async {
    final json = await _postJson('/api/login', {
      'username': username,
      'password': password,
    });
    return AuthSession.fromJson(json);
  }

  Future<void> logout(String token) async {
    await _postJson('/api/logout', null, token: token);
  }

  Future<UserProfile> me(String token) async {
    final json = await _getJson('/api/me', token);
    return UserProfile.fromJson(json['user'] as Map<String, dynamic>? ?? {});
  }

  // ---------- 基础请求 ----------

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic>? body, {
    String? token,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    try {
      final resp = await _http
          .post(Uri.parse('$_base$path'),
              headers: headers,
              body: body == null ? null : jsonEncode(body))
          .timeout(_timeout);
      return _decode(resp);
    } on SocketException {
      throw ApiException('无法连接服务器，请检查网络');
    } on TimeoutException {
      throw ApiException('连接服务器超时');
    } on http.ClientException {
      throw ApiException('无法连接服务器（连接被拒绝或证书不匹配）');
    } on TlsException {
      throw ApiException('服务器证书校验失败');
    }
  }

  Future<Map<String, dynamic>> _getJson(String path, String token) async {
    try {
      final resp = await _http.get(
        Uri.parse('$_base$path'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_timeout);
      return _decode(resp);
    } on SocketException {
      throw ApiException('无法连接服务器，请检查网络');
    } on TimeoutException {
      throw ApiException('连接服务器超时');
    } on http.ClientException {
      throw ApiException('无法连接服务器（连接被拒绝或证书不匹配）');
    } on TlsException {
      throw ApiException('服务器证书校验失败');
    }
  }

  Map<String, dynamic> _decode(http.Response resp) {
    Map<String, dynamic> json = {};
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    } on FormatException {
      // 非 JSON 响应，走通用错误
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) return json;

    // FastAPI 错误形状是 {"detail": "..."}
    final detail = json['detail'];
    final message = detail is String && detail.isNotEmpty
        ? detail
        : '请求失败（${resp.statusCode}）';
    throw ApiException(message, statusCode: resp.statusCode);
  }
}
