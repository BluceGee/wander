/// APP 后端服务地址（账号服务 + LLM 薄代理）。
///
/// [certPin] 是服务器自签证书的 SHA-256 指纹（openssl 显示的那种，
/// 冒号可有可无）。留空则走系统证书校验（配了正式域名证书时用）。
class ServerConfig {
  /// 后端地址（https，端口 8443）。
  static const baseUrl = 'https://115.190.50.101:8443';

  /// 部署前占位符：视同「未配置」。
  static const certPinPlaceholder = '__CERT_PIN__';

  /// 服务器证书指纹（部署后生成，见 server/README.md）。
  static const certPin =
      '69d313d2a0d6673973df43c2f9fe294e774b8ee2f22c37b62dd85fa018600485';
}
