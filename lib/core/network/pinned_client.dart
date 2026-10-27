import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'server_config.dart';

/// 创建带「证书固定」的 HTTP 客户端。
///
/// - [certPin] 为空（或仍是部署前占位符）时返回普通客户端；
/// - 否则只额外放行证书指纹与 pin 一致的自签证书。
///
/// 普通 CA 签发的证书（如 Claude API）走系统信任链，不会进入
/// `badCertificateCallback`，因此同一客户端可同时用于代理与直连。
http.Client createPinnedClient(String certPin) {
  final pin = normalizePin(certPin);
  if (pin.isEmpty || pin == normalizePin(ServerConfig.certPinPlaceholder)) {
    return http.Client();
  }
  final io = HttpClient();
  io.badCertificateCallback = (cert, host, port) {
    final digest = sha256.convert(cert.der).toString();
    return digest == pin;
  };
  return IOClient(io);
}

/// 去掉冒号与空白并转小写，便于填入 openssl 风格指纹。
String normalizePin(String pin) =>
    pin.replaceAll(RegExp(r'[:\s]'), '').toLowerCase();
