import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/vault/vault_crypto.dart';

void main() {
  group('VaultCrypto keyslot wrap/unwrap', () {
    test('正确口令能解开 keyslot', () async {
      final mk = await VaultCrypto.generateMasterKey();
      final slot = await VaultCrypto.wrapMasterKey(mk, 'correct horse battery staple');

      final unwrapped = await VaultCrypto.tryUnwrapMasterKey(slot, 'correct horse battery staple');

      expect(unwrapped, isNotNull);
      final expectedBytes = await mk.extractBytes();
      final actualBytes = await unwrapped!.extractBytes();
      expect(actualBytes, expectedBytes);
    });

    test('错误口令解不开 keyslot，返回 null', () async {
      final mk = await VaultCrypto.generateMasterKey();
      final slot = await VaultCrypto.wrapMasterKey(mk, 'correct horse battery staple');

      final unwrapped = await VaultCrypto.tryUnwrapMasterKey(slot, 'wrong password');

      expect(unwrapped, isNull);
    });

    test('keyslot 长度固定为 76 字节', () async {
      final mk = await VaultCrypto.generateMasterKey();
      final slot = await VaultCrypto.wrapMasterKey(mk, 'x' * 12);
      expect(slot.length, 76);
    });

    test('截断的 keyslot 返回 null，不抛异常', () async {
      final mk = await VaultCrypto.generateMasterKey();
      final slot = await VaultCrypto.wrapMasterKey(mk, 'CorrectHorse1');
      expect(
        await VaultCrypto.tryUnwrapMasterKey(
          Uint8List.fromList(slot.sublist(0, 20)),
          'CorrectHorse1',
        ),
        isNull,
      );
    });
  });

  group('VaultCrypto blob encrypt/decrypt', () {
    test('加密后能用同一把主密钥解回原文', () async {
      final mk = await VaultCrypto.generateMasterKey();
      final plaintext = Uint8List.fromList('隐私日记内容'.codeUnits);

      final packed = await VaultCrypto.encryptBlob(mk, plaintext);
      final decrypted = await VaultCrypto.decryptBlob(mk, packed);

      expect(decrypted, plaintext);
    });

    test('用不同主密钥解密返回 null', () async {
      final mk1 = await VaultCrypto.generateMasterKey();
      final mk2 = await VaultCrypto.generateMasterKey();
      final packed = await VaultCrypto.encryptBlob(mk1, Uint8List.fromList([1, 2, 3]));

      final decrypted = await VaultCrypto.decryptBlob(mk2, packed);

      expect(decrypted, isNull);
    });

    test('长度不足的 blob 返回 null，不抛异常', () async {
      final mk = await VaultCrypto.generateMasterKey();
      expect(
        await VaultCrypto.decryptBlob(mk, Uint8List.fromList([1, 2, 3])),
        isNull,
      );
    });
  });

  group('VaultCrypto.generateRecoveryCode', () {
    test('生成 24 位字符，且不含易混字符 0/O/1/I/L', () {
      final code = VaultCrypto.generateRecoveryCode();
      expect(code.length, 24);
      expect(code.contains(RegExp(r'[0O1IL]')), isFalse);
    });

    test('恢复码本身满足 ASCII 可打印约束', () {
      expect(VaultCrypto.isAsciiPrintable(VaultCrypto.generateRecoveryCode()), isTrue);
    });
  });

  group('VaultCrypto.isAsciiPrintable', () {
    test('纯 ASCII 口令通过', () {
      expect(VaultCrypto.isAsciiPrintable('CorrectHorse1'), isTrue);
    });

    test('含中文的口令不通过', () {
      expect(VaultCrypto.isAsciiPrintable('口令Abc123'), isFalse);
    });

    test('含空格不通过（0x20 在可打印范围之外）', () {
      expect(VaultCrypto.isAsciiPrintable('Correct Horse1'), isFalse);
    });

    test('含 emoji 不通过', () {
      expect(VaultCrypto.isAsciiPrintable('Abc123🙂'), isFalse);
    });
  });
}
