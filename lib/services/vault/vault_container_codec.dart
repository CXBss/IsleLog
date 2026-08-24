import 'dart:convert';
import 'dart:typed_data';

import '../../data/models/vault_entry.dart';

/// 附件容器的简单 TLV 编解码——不用 zip：照片/录音本身已是压缩格式，
/// DEFLATE 收益接近零，不值得引入额外依赖。
///
/// 格式：[4B BE count] 重复 { [2B BE idLen][id utf8] [2B BE mimeLen][mime utf8] [4B BE dataLen][data] }
class VaultContainerCodec {
  VaultContainerCodec._();

  static Uint8List encodeAttachments(List<VaultAttachment> items) {
    final builder = BytesBuilder();
    builder.add(_uint32(items.length));
    for (final item in items) {
      final idBytes = utf8.encode(item.id);
      final mimeBytes = utf8.encode(item.mimeType);
      if (idBytes.length > 0xFFFF || mimeBytes.length > 0xFFFF) {
        throw FormatException('vault 附件的 id/mime 长度超出 TLV 上限');
      }
      builder.add(_uint16(idBytes.length));
      builder.add(idBytes);
      builder.add(_uint16(mimeBytes.length));
      builder.add(mimeBytes);
      builder.add(_uint32(item.bytes.length));
      builder.add(item.bytes);
    }
    return builder.toBytes();
  }

  static List<VaultAttachment> decodeAttachments(Uint8List data) {
    if (data.length < 4) {
      throw const FormatException('附件容器长度不足');
    }
    final view = ByteData.sublistView(data);
    var offset = 0;
    final count = view.getUint32(offset, Endian.big);
    offset += 4;
    final result = <VaultAttachment>[];
    for (var i = 0; i < count; i++) {
      if (offset + 2 > data.length) {
        throw const FormatException('附件容器 idLen 越界');
      }
      final idLen = view.getUint16(offset, Endian.big);
      offset += 2;
      if (offset + idLen > data.length) {
        throw const FormatException('附件容器 id 越界');
      }
      final id = utf8.decode(data.sublist(offset, offset + idLen));
      offset += idLen;

      if (offset + 2 > data.length) {
        throw const FormatException('附件容器 mimeLen 越界');
      }
      final mimeLen = view.getUint16(offset, Endian.big);
      offset += 2;
      if (offset + mimeLen > data.length) {
        throw const FormatException('附件容器 mime 越界');
      }
      final mime = utf8.decode(data.sublist(offset, offset + mimeLen));
      offset += mimeLen;

      if (offset + 4 > data.length) {
        throw const FormatException('附件容器 dataLen 越界');
      }
      final dataLen = view.getUint32(offset, Endian.big);
      offset += 4;
      if (offset + dataLen > data.length) {
        throw const FormatException('附件容器 data 越界');
      }
      final bytes = Uint8List.fromList(data.sublist(offset, offset + dataLen));
      offset += dataLen;

      result.add(VaultAttachment(id: id, mimeType: mime, bytes: bytes));
    }
    return result;
  }

  static Uint8List _uint16(int value) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.big);

  static Uint8List _uint32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);
}
