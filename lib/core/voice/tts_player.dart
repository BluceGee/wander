import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// TTS 音频播放（WAV 字节），语音播报用。
class TtsPlayer {
  AudioPlayer? _player;
  bool _playing = false;

  bool get isPlaying => _playing;

  /// 播放 WAV 字节（先停掉上一段再播）。
  Future<void> play(Uint8List wavBytes) async {
    await stop();
    final player = AudioPlayer();
    _player = player;
    _playing = true;
    player.onPlayerComplete.listen((_) {
      if (identical(_player, player)) {
        _player = null;
        _playing = false;
      }
    });
    try {
      await player.play(BytesSource(wavBytes));
    } catch (_) {
      if (identical(_player, player)) {
        _player = null;
        _playing = false;
      }
      rethrow;
    }
  }

  /// 停止播放。
  Future<void> stop() async {
    final player = _player;
    _player = null;
    _playing = false;
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
  }

  Future<void> dispose() => stop();
}
