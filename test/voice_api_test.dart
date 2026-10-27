import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:xnl/core/voice/voice_api.dart';

void main() {
  group('AsrClient', () {
    test('发 input_audio 形状并解析识别文本', () async {
      late http.Request captured;
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': ' 记一笔午饭二十五元 '}
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final wav = Uint8List.fromList([82, 73, 70, 70, 1, 2, 3]); // RIFF…
      final client =
          AsrClient(apiKey: 'tp-test', httpClient: mockClient);
      final text = await client.transcribe(wav);

      expect(captured.url.toString(), '$kAudioApiBase/chat/completions');
      expect(captured.headers['authorization'], 'Bearer tp-test');
      final body =
          jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body['model'], kAsrModel);
      final message = (body['messages'] as List).single as Map<String, dynamic>;
      expect(message['role'], 'user');
      final content = (message['content'] as List).single as Map<String, dynamic>;
      expect(content['type'], 'input_audio');
      expect(content['input_audio']['format'], 'wav');
      expect(content['input_audio']['data'], base64Encode(wav));

      expect(text, '记一笔午饭二十五元');
    });

    test('非 200 抛 VoiceApiException 并提取错误信息', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({
              'error': {'message': 'ASR request requires input_audio', 'param': 'messages'}
            }),
            400,
          ));
      final client = AsrClient(apiKey: 'k', httpClient: mockClient);
      expect(
        () => client.transcribe(Uint8List(4)),
        throwsA(isA<VoiceApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('input_audio'))),
      );
    });
  });

  group('TtsClient', () {
    test('发 assistant 消息形状并解码 base64 WAV', () async {
      late http.Request captured;
      final wav = Uint8List.fromList([82, 73, 70, 70, 9, 8]);
      final mockClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'audio': {'data': base64Encode(wav)},
                }
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = TtsClient(apiKey: 'tp-test', httpClient: mockClient);
      final out = await client.synthesize('好的，已记下');

      expect(captured.url.toString(), '$kAudioApiBase/chat/completions');
      expect(captured.headers['authorization'], 'Bearer tp-test');
      final body =
          jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body['model'], kTtsModel);
      final message = (body['messages'] as List).single as Map<String, dynamic>;
      expect(message['role'], 'assistant');
      expect(message['content'], '好的，已记下');

      expect(out, wav);
    });

    test('回复不含音频时抛 VoiceApiException', () async {
      final mockClient = MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': '没有音频'}
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final client = TtsClient(apiKey: 'k', httpClient: mockClient);
      expect(
        () => client.synthesize('你好'),
        throwsA(isA<VoiceApiException>()
            .having((e) => e.message, 'message', contains('音频'))),
      );
    });
  });
}
