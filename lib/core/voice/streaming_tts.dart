import 'dart:typed_data';

import 'tts_player.dart';
import 'voice_api.dart';

/// 流式 TTS 跟读队列：文字边流出，边切句、合成、顺序播放（豆包式）。
///
/// MiMo TTS 一次合成一整段文本，所以「跟读流式」的做法是：
/// [feed] 收到流式文字增量后按句切分，每凑完一句立刻送去合成，
/// 合成好就排队等上一段播完再播；[flush] 在流结束时把没有句号的
/// 尾巴也读掉；[stop] 清空队列并立刻闭嘴（关播报/新提问时调用）。
class StreamingTtsQueue {
  StreamingTtsQueue({
    required this._apiKeyOf,
    SpeechPlayer? player,
    this._synthesizer,
    TtsClient Function(String apiKey)? clientFactory,
  })  : _player = player ?? TtsPlayer(),
        _clientFactory = clientFactory ?? ((key) => TtsClient(apiKey: key));

  final String Function() _apiKeyOf;
  final SpeechPlayer _player;
  final Future<Uint8List> Function(String text)? _synthesizer;
  final TtsClient Function(String apiKey) _clientFactory;

  /// 单句兜底长度：超过还没遇到标点就强制切（防止一直不张嘴）。
  static const _maxSegment = 80;

  static const _hardEnds = '。！？；!?;\n…';

  final List<String> _pending = [];
  String _buffer = '';
  int _generation = 0;
  Future<void>? _draining;

  /// 还在排队/播放的句子数（测试与调试用）。
  int get pendingCount => _pending.length;

  /// 当前这一轮切句-合成-播放全部完成（测试等待用）。
  Future<void> get idle => _draining ?? Future.value();

  /// 喂入一段流式文字增量，凑够一句就送去合成播放。
  void feed(String delta) {
    if (delta.isEmpty) return;
    _buffer += delta;
    _cut();
    _ensureWorker();
  }

  /// 流结束：把剩下的尾巴（可能没有句号）也送去读。
  void flush() {
    final tail = _buffer.trim();
    _buffer = '';
    if (tail.isNotEmpty) _pending.add(tail);
    _ensureWorker();
  }

  /// 立刻闭嘴并清空队列（关播报 / 新一轮提问）。
  Future<void> stop() async {
    _generation++;
    _pending.clear();
    _buffer = '';
    _draining = null;
    await _player.stop();
  }

  Future<void> dispose() => stop();

  /// 从缓冲里切出所有完整的句子进队列。
  void _cut() {
    while (true) {
      final hard = _findHardCut(_buffer);
      if (hard != null) {
        _emit(_buffer.substring(0, hard));
        _buffer = _buffer.substring(hard);
        continue;
      }
      // 超长还没标点：在靠后的逗号处切，没有逗号就硬切
      if (_buffer.length > _maxSegment) {
        final comma = _buffer.lastIndexOf('，', _maxSegment);
        final cut = comma > 20 ? comma + 1 : _maxSegment;
        _emit(_buffer.substring(0, cut));
        _buffer = _buffer.substring(cut);
        continue;
      }
      break;
    }
  }

  /// 找第一个句末标点的位置（含标点与紧跟的收尾引号）。
  int? _findHardCut(String s) {
    for (var i = 0; i < s.length; i++) {
      if (!_hardEnds.contains(s[i])) continue;
      var end = i + 1;
      while (end < s.length && '」』）】"\'}）"'.contains(s[end])) {
        end++;
      }
      return end;
    }
    return null;
  }

  void _emit(String raw) {
    final text = raw.trim();
    if (text.isNotEmpty) _pending.add(text);
  }

  void _ensureWorker() {
    if (_draining != null || _pending.isEmpty) return;
    final gen = _generation;
    // identical 守卫：stop() 后旧 drain 的收尾不能清掉新 drain 的跟踪
    late final Future<void> self;
    self = _drain(gen).whenComplete(() {
      if (!identical(_draining, self)) return;
      _draining = null;
      // 收尾瞬间又进了新句子：接着跑，别让队列晾着
      if (gen == _generation) _ensureWorker();
    });
    _draining = self;
  }

  Future<void> _drain(int gen) async {
    while (gen == _generation && _pending.isNotEmpty) {
      final sentence = _pending.removeAt(0);
      Uint8List? wav;
      try {
        wav = await _synthesize(sentence);
      } on Exception {
        continue; // 单句合成失败跳过，不打断整段跟读
      }
      if (gen != _generation) return; // 已被 stop/新一轮打断
      if (wav.isEmpty) continue;
      try {
        await _player.playAndAwait(wav);
      } on Exception {
        // 播放失败也继续下一句
      }
    }
  }

  Future<Uint8List> _synthesize(String text) {
    final synthesizer = _synthesizer;
    if (synthesizer != null) return synthesizer(text);
    final apiKey = _apiKeyOf();
    if (apiKey.isEmpty) {
      throw const VoiceApiException('未配置 API Key');
    }
    return _clientFactory(apiKey).synthesize(text);
  }
}
