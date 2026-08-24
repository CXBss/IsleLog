import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/vault/vault_audio_source.dart';

void main() {
  test('request() 返回与输入字节等长的完整流', () async {
    final bytes = Uint8List.fromList(List.generate(100, (i) => i));
    final source = VaultByteAudioSource(bytes, mimeType: 'audio/aac');

    final response = await source.request();
    final collected = <int>[];
    await for (final chunk in response.stream) {
      collected.addAll(chunk);
    }

    expect(response.contentLength, 100);
    expect(collected, bytes);
  });

  test('request(start, end) 只返回指定区间', () async {
    final bytes = Uint8List.fromList(List.generate(100, (i) => i));
    final source = VaultByteAudioSource(bytes, mimeType: 'audio/aac');

    final response = await source.request(10, 20);
    final collected = <int>[];
    await for (final chunk in response.stream) {
      collected.addAll(chunk);
    }

    expect(collected, bytes.sublist(10, 20));
  });
}
