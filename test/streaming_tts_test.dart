import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xnl/core/voice/streaming_tts.dart';
import 'package:xnl/core/voice/tts_player.dart';

/// 假播放器：记录播放顺序，立即"播完"。
class _FakePlayer implements SpeechPlayer {
  final List<String> played = [];
  int stopCalls = 0;

  @override
  Future<void> playAndAwait(Uint8List wavBytes) async {
    played.add(utf8.decode(wavBytes));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

/// 合成器：文本原样编码成"wav"，便于断言播放内容与顺序。
Future<Uint8List> _fakeSynthesize(String text) async =>
    Uint8List.fromList(utf8.encode(text));

StreamingTtsQueue _build({_FakePlayer? player}) => StreamingTtsQueue(
      apiKeyOf: () => 'k',
      player: player ?? _FakePlayer(),
      synthesizer: _fakeSynthesize,
    );

void main() {
  group('StreamingTtsQueue 切句', () {
    test('按句末标点切句，增量喂入', () async {
      final player = _FakePlayer();
      final q = _build(player: player);

      q.feed('你好，');
      q.feed('今天天气不错。');
      expect(player.played, isEmpty, reason: '没到句号不该播');

      q.feed('明天记得带伞！');
      await q.idle;
      expect(player.played, ['你好，今天天气不错。', '明天记得带伞！']);
    });

    test('流结束 flush 读掉无标点尾巴', () async {
      final player = _FakePlayer();
      final q = _build(player: player);

      q.feed('好的马上安排');
      await q.idle;
      expect(player.played, isEmpty);

      q.flush();
      await q.idle;
      expect(player.played, ['好的马上安排']);
    });

    test('超长无标点在逗号处切', () async {
      final player = _FakePlayer();
      final q = _build(player: player);
      final long = '这一句话特别特别长没有句号只有逗号，然后继续说下去一直说到超过八十个字符的长度为止，'
          '再来一段继续凑字数一直到彻底超过长度限制为止，最后又补了一大段话确保它真的很长很长很长';

      q.feed(long);
      await q.idle;
      q.flush(); // 尾巴没句号，flush 后才读
      await q.idle;
      expect(player.played.join(), long);
      expect(player.played.length, greaterThan(1), reason: '超长应切成多段');
      for (final seg in player.played) {
        expect(seg.length, lessThanOrEqualTo(100));
      }
    });

    test('收尾引号跟句子一起切', () async {
      final player = _FakePlayer();
      final q = _build(player: player);

      q.feed('他说「该起床了。」然后关了灯。');
      await q.idle;
      expect(player.played, ['他说「该起床了。」', '然后关了灯。']);
    });

    test('空增量与空白尾巴不产生播放', () async {
      final player = _FakePlayer();
      final q = _build(player: player);

      q.feed('');
      q.feed('   ');
      q.flush();
      await q.idle;
      expect(player.played, isEmpty);
    });
  });

  group('StreamingTtsQueue 控制', () {
    test('stop 清空队列并打断', () async {
      final player = _FakePlayer();
      final q = _build(player: player);

      q.feed('第一句。第二句还没出来');
      await q.stop();
      q.flush(); // stop 之后的 flush 不该把已清掉的内容读出来
      await q.idle;

      expect(player.played, isEmpty, reason: 'stop 立刻打断：合成中的句子也丢弃，buffer 已清');
      expect(player.stopCalls, greaterThanOrEqualTo(1));
      expect(q.pendingCount, 0);
    });

    test('stop 之后可以继续 feed（新一段回复）', () async {
      final player = _FakePlayer();
      final q = _build(player: player);

      q.feed('旧回复的一句。');
      await q.idle;
      await q.stop();

      q.feed('新回复来了。');
      await q.idle;
      expect(player.played, ['旧回复的一句。', '新回复来了。']);
    });

    test('合成失败跳过该句，不打断后续', () async {
      final player = _FakePlayer();
      var failNext = false;
      final q = StreamingTtsQueue(
        apiKeyOf: () => 'k',
        player: player,
        synthesizer: (text) async {
          if (failNext) {
            failNext = false;
            throw Exception('boom');
          }
          return _fakeSynthesize(text);
        },
      );

      failNext = true;
      q.feed('这句合成会失败。接下来一句正常。');
      await q.idle;
      expect(player.played, ['接下来一句正常。']);
    });
  });
}
