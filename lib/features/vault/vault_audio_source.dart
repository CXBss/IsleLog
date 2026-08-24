import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// 从内存字节播放音频，不落地临时文件——vault 的附件解密后只应存在于内存。
class VaultByteAudioSource extends StreamAudioSource {
  final Uint8List bytes;
  final String mimeType;

  VaultByteAudioSource(this.bytes, {required this.mimeType, super.tag});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream.value(bytes.sublist(s, e)),
      contentType: mimeType,
    );
  }
}
