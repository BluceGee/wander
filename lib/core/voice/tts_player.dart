import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// 播放器抽象：流式播报队列依赖「播完一段再播下一段」的完成信号。
abstract class SpeechPlayer {
  /// 播放 WAV 字节并等这一段播完。
  Future<void> playAndAwait(Uint8List wavBytes);

  /// 停止播放（中断当前段）。
  Future<void> stop();
}

/// TTS 音频播放（WAV 字节），语音播报用。
class TtsPlayer implements SpeechPlayer {
  AudioPlayer? _player;
  Completer<void>? _done;
  bool _playing = false;

  bool get isPlaying => _playing;

  /// 播放 WAV 字节并等这一段播完（顺序播报依赖完成信号）。
  @override
  Future<void> playAndAwait(Uint8List wavBytes) async {
    await stop();
    final player = AudioPlayer();
    final done = Completer<void>();
    _player = player;
    _done = done;
    _playing = true;
    void finish() {
      if (identical(_player, player)) {
        _player = null;
        _playing = false;
      }
      if (!done.isCompleted) done.complete();
    }

    final sub = player.onPlayerComplete.listen((_) => finish());
    try {
      await player.play(BytesSource(wavBytes));
      await done.future;
    } catch (_) {
      finish(); // 播放失败也放行队列，不卡住后续句子
    } finally {
      await sub.cancel();
    }
  }

  /// 停止播放（同时放行正在等待的完成信号，防止队列卡死）。
  @override
  Future<void> stop() async {
    final player = _player;
    final done = _done;
    _player = null;
    _done = null;
    _playing = false;
    if (done != null && !done.isCompleted) done.complete();
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
  }

  Future<void> dispose() => stop();
}
