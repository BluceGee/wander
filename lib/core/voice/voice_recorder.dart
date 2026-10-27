import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// 麦克风录音（16kHz 单声道 WAV），供 [AsrClient] 识别。
///
/// [asr] 相关见 voice_api.dart；这里只负责收音与权限。
class VoiceRecorder {
  AudioRecorder? _recorder;
  bool _recording = false;

  bool get isRecording => _recording;

  /// 请求麦克风权限；被拒返回 false。
  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// 开始录音（写入临时 WAV 文件）。
  Future<void> start() async {
    await stop(); // 防御：上一段没停干净先停掉
    final recorder = AudioRecorder();
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/asr_${DateTime.now().microsecondsSinceEpoch}.wav';
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _recorder = recorder;
    _recording = true;
  }

  /// 停止录音并返回 WAV 字节；无内容返回 null。
  Future<Uint8List?> stop() async {
    final recorder = _recorder;
    _recorder = null;
    _recording = false;
    if (recorder == null) return null;
    final path = await recorder.stop();
    await recorder.dispose();
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes.isEmpty ? null : bytes;
  }

  Future<void> dispose() async {
    await stop();
  }
}
