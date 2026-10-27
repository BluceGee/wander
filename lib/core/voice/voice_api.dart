import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// MiMo 语音接口：ASR（语音识别）/ TTS（语音合成）。
///
/// 与对话（Anthropic Messages）不同，语音模型走 MiMo 的
/// `/v1/chat/completions`（平台的语音调用方式）：
/// - ASR：user 消息带 `input_audio` 内容块（base64 音频）→ 回复文本即识别结果；
/// - TTS：assistant 消息即待合成文本 → `choices[0].message.audio.data` 为 base64 WAV。
const kAudioApiBase = 'https://token-plan-cn.xiaomimimo.com/v1';

/// 语音识别模型（写死）。
const kAsrModel = 'mimo-v2.5-asr';

/// 语音合成模型（写死）。
const kTtsModel = 'mimo-v2.5-tts';

/// 语音接口调用失败。[statusCode] 为 null 表示网络层错误。
class VoiceApiException implements Exception {
  const VoiceApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'VoiceApiException(${statusCode == null ? 'network' : 'HTTP $statusCode'}: $message)';
}

/// 语音识别客户端（mimo-v2.5-asr）。
class AsrClient {
  AsrClient({required this.apiKey, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _http;

  /// 识别 WAV 音频（16bit PCM）为文字。
  Future<String> transcribe(Uint8List wavBytes) async {
    final body = jsonEncode({
      'model': kAsrModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_audio',
              'input_audio': {
                'data': base64Encode(wavBytes),
                'format': 'wav',
              },
            }
          ],
        }
      ],
    });

    final http.Response res;
    try {
      res = await _http.post(
        Uri.parse('$kAudioApiBase/chat/completions'),
        headers: _headers,
        body: body,
      );
    } on Exception catch (e) {
      throw VoiceApiException('网络请求失败：$e');
    }
    final json = _decodeOrThrow(res);
    final choices = json['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) {
      throw const VoiceApiException('识别结果为空');
    }
    final message =
        (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>? ?? const {};
    return (message['content'] as String? ?? '').trim();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      };

  Map<String, dynamic> _decodeOrThrow(http.Response res) {
    if (res.statusCode != 200) {
      throw VoiceApiException(_errorMessage(res.body), statusCode: res.statusCode);
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on Exception catch (e) {
      throw VoiceApiException('响应不是合法 JSON：$e', statusCode: res.statusCode);
    }
  }
}

/// 语音合成客户端（mimo-v2.5-tts）。
class TtsClient {
  TtsClient({required this.apiKey, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _http;

  /// 把 [text] 合成为 WAV 音频字节。
  Future<Uint8List> synthesize(String text) async {
    final body = jsonEncode({
      'model': kTtsModel,
      'messages': [
        {'role': 'assistant', 'content': text},
      ],
    });

    final http.Response res;
    try {
      res = await _http.post(
        Uri.parse('$kAudioApiBase/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${apiKey.trim()}',
        },
        body: body,
      );
    } on Exception catch (e) {
      throw VoiceApiException('网络请求失败：$e');
    }

    if (res.statusCode != 200) {
      throw VoiceApiException(_errorMessage(res.body), statusCode: res.statusCode);
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on Exception catch (e) {
      throw VoiceApiException('响应不是合法 JSON：$e', statusCode: res.statusCode);
    }

    final choices = json['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) {
      throw const VoiceApiException('合成结果为空');
    }
    final message =
        (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>? ?? const {};
    final audio = message['audio'] as Map<String, dynamic>?;
    final data = audio?['data'] as String?;
    if (data == null || data.isEmpty) {
      throw const VoiceApiException('合成结果不含音频');
    }
    return base64Decode(data);
  }
}

/// 解析平台错误体 `{"error":{"message":...}}`，取不到则截断原文。
String _errorMessage(String body) {
  try {
    final json = jsonDecode(body);
    if (json is Map<String, dynamic>) {
      final err = json['error'];
      if (err is Map<String, dynamic> && err['message'] is String) {
        final param = err['param'];
        final suffix = param is String && param.isNotEmpty ? '：$param' : '';
        return '${err['message']}$suffix';
      }
    }
  } on FormatException {
    // 非 JSON 错误体，走截断
  }
  return body.length <= 400 ? body : '${body.substring(0, 400)}…';
}
