import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 隐私空间的密钥派生与加解密（纯函数，不涉及文件 IO）。
///
/// 主密钥（Master Key，MK）随机生成，不直接由口令派生——
/// 这样可以用两把不同的凭证（口令 / 恢复码）分别包裹同一把 MK，
/// 而不需要维护两份独立加密的数据。
///
/// keyslot 格式（76 字节）：[16B salt][12B nonce][32B wrapped-MK][16B mac]
/// blob 格式：[12B nonce][ciphertext][16B mac]
class VaultCrypto {
  VaultCrypto._();

  static final _kdf = Argon2id(
    parallelism: 1,
    memory: 32000, // KiB，≈32MB
    iterations: 2,
    hashLength: 32,
  );

  static final _aead = AesGcm.with256bits();

  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;
  static const _mkLength = 32;

  static Uint8List generateSalt() => _randomBytes(_saltLength);

  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rnd.nextInt(256)));
  }

  static Future<SecretKey> generateMasterKey() => _aead.newSecretKey();

  static Future<SecretKey> _deriveKek(String passphrase, Uint8List salt) {
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  /// 口令是否只含 ASCII 可打印字符（0x21–0x7E）。
  ///
  /// 创建时强制这一条，从根上消掉 Unicode 归一化问题：非 ASCII 口令
  /// （中文、带重音的拉丁字母、emoji）在不同输入法/系统版本下会产生不同的
  /// Unicode 组合形式，同一个口令在新手机上可能派生出不同的密钥、解不开数据
  /// ——换机恢复场景下这是致命的。
  ///
  /// 选择"限制字符集"而不是"引入 NFC 归一化库"：创建口令本来就要求
  /// 大小写字母 + 数字，本身已经强烈指向 ASCII；为一个用户几乎不会踩、
  /// 且踩到就是数据丢失的边界情况引入一个额外依赖不划算。
  static bool isAsciiPrintable(String s) =>
      s.isNotEmpty && s.codeUnits.every((c) => c >= 0x21 && c <= 0x7E);

  static Future<Uint8List> wrapMasterKey(
    SecretKey masterKey,
    String passphrase,
  ) async {
    final salt = generateSalt();
    final kek = await _deriveKek(passphrase, salt);
    final mkBytes = await masterKey.extractBytes();
    final box = await _aead.encrypt(mkBytes, secretKey: kek);
    final packed = box.concatenation(nonce: true, mac: true);
    return Uint8List.fromList([...salt, ...packed]);
  }

  static Future<SecretKey?> tryUnwrapMasterKey(
    Uint8List keyslot76,
    String passphrase,
  ) async {
    if (keyslot76.length !=
        _saltLength + _nonceLength + _mkLength + _macLength) {
      return null;
    }
    final salt = keyslot76.sublist(0, _saltLength);
    final rest = keyslot76.sublist(_saltLength);
    final kek = await _deriveKek(passphrase, salt);
    try {
      final box = SecretBox.fromConcatenation(
        rest,
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final mkBytes = await _aead.decrypt(box, secretKey: kek);
      return SecretKey(mkBytes);
    } catch (_) {
      // GCM 失败、格式异常一律 null——调用方需要"打不开"这一个语义，
      // 不允许任何异常冒泡（那会暴露特殊代码路径）。
      return null;
    }
  }

  static Future<Uint8List> encryptBlob(
    SecretKey masterKey,
    Uint8List plaintext,
  ) async {
    final box = await _aead.encrypt(plaintext, secretKey: masterKey);
    return box.concatenation(nonce: true, mac: true);
  }

  static Future<Uint8List?> decryptBlob(
    SecretKey masterKey,
    Uint8List packed,
  ) async {
    if (packed.length < _nonceLength + _macLength) return null;
    try {
      final box = SecretBox.fromConcatenation(
        packed,
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final plaintext = await _aead.decrypt(box, secretKey: masterKey);
      return Uint8List.fromList(plaintext);
    } catch (_) {
      return null;
    }
  }

  static const _recoveryAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// 恢复码长度。解锁时据此判断"要不要试恢复码槽"，见 VaultStorage。
  static const recoveryCodeLength = 24;

  static String generateRecoveryCode() {
    final rnd = Random.secure();
    return List.generate(
      recoveryCodeLength,
      (_) => _recoveryAlphabet[rnd.nextInt(_recoveryAlphabet.length)],
    ).join();
  }
}
