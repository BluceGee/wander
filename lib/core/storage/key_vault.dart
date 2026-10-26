import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 敏感配置（API Key）的存取接口。
///
/// 正式实现 [FlutterKeyVault] 存 Android Keystore 加密存储；
/// 测试注入 [InMemoryKeyVault]，不碰平台通道。
abstract class KeyVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// 基于 flutter_secure_storage 的实现（Android Keystore 加密）。
class FlutterKeyVault implements KeyVault {
  const FlutterKeyVault();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 测试用内存实现。
class InMemoryKeyVault implements KeyVault {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}
