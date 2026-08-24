import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/vault_entry.dart';
import 'package:isle_log/services/vault/vault_container_codec.dart';

void main() {
  test('编码后解码能还原空列表', () {
    final decoded = VaultContainerCodec.decodeAttachments(
      VaultContainerCodec.encodeAttachments(const []),
    );
    expect(decoded, isEmpty);
  });

  test('编码后解码能还原多个附件的全部字段', () {
    final items = [
      VaultAttachment(
        id: 'att-1',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
      ),
      VaultAttachment(
        id: 'att-2',
        mimeType: 'audio/aac',
        bytes: Uint8List.fromList(List.generate(1000, (i) => i % 256)),
      ),
    ];

    final decoded = VaultContainerCodec.decodeAttachments(
      VaultContainerCodec.encodeAttachments(items),
    );

    expect(decoded.length, 2);
    expect(decoded[0].id, 'att-1');
    expect(decoded[0].mimeType, 'image/jpeg');
    expect(decoded[0].bytes, items[0].bytes);
    expect(decoded[1].id, 'att-2');
    expect(decoded[1].bytes, items[1].bytes);
  });

  test('截断的容器抛 FormatException（由调用方 catch）', () {
    expect(
      () => VaultContainerCodec.decodeAttachments(
        Uint8List.fromList([0, 0, 0, 1, 0, 10]),
      ),
      throwsFormatException,
    );
  });
}
