import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/vault/vault_entry_gate.dart';

VaultInputKind _classify(
  String raw, {
  bool vaultExists = false,
  bool serverConfigured = false,
}) => VaultEntryGate.classify(
  raw,
  vaultExists: vaultExists,
  serverConfigured: serverConfigured,
);

void main() {
  group('创建（+ 前缀）', () {
    test('含大小写和数字、无本地 vault → create', () {
      expect(_classify('+CorrectHorse1'), VaultInputKind.create);
    });

    test('全小写+数字，强度不够 → none（按普通搜索处理）', () {
      expect(_classify('+correcthorse1'), VaultInputKind.none);
    });

    test('缺数字 → none', () {
      expect(_classify('+CorrectHorse'), VaultInputKind.none);
    });

    test('长度不足 8 → none', () {
      expect(_classify('+Ab1'), VaultInputKind.none);
    });

    test('含空格 → none', () {
      expect(_classify('+Correct Horse1'), VaultInputKind.none);
    });

    test('已有本地 vault 时 + 前缀失效 → none', () {
      expect(_classify('+CorrectHorse1', vaultExists: true), VaultInputKind.none);
    });
  });

  group('解锁（无前缀）', () {
    test('有本地 vault、长度够 → unlock', () {
      expect(_classify('correcthorse1', vaultExists: true), VaultInputKind.unlock);
    });

    test('解锁不要求大小写+数字组合', () {
      expect(_classify('alllowercase', vaultExists: true), VaultInputKind.unlock);
    });

    test('非 ASCII（中文搜索词）不触发 KDF', () {
      expect(
        _classify('今天天气怎么样啊', vaultExists: true),
        VaultInputKind.none,
      );
    });

    test('无本地 vault → none', () {
      expect(_classify('correcthorse1'), VaultInputKind.none);
    });

    test('长度不足 → none', () {
      expect(_classify('short', vaultExists: true), VaultInputKind.none);
    });

    test('含空格 → none（正常的多词搜索不该触发 KDF）', () {
      expect(_classify('tomorrow morning', vaultExists: true), VaultInputKind.none);
    });
  });

  group('恢复（? 前缀）', () {
    test('无本地 vault、已配服务端 → recover', () {
      expect(
        _classify('?correcthorse1', serverConfigured: true),
        VaultInputKind.recover,
      );
    });

    test('未配服务端 → none', () {
      expect(_classify('?correcthorse1'), VaultInputKind.none);
    });

    test('已有本地 vault → none', () {
      expect(
        _classify('?correcthorse1', vaultExists: true, serverConfigured: true),
        VaultInputKind.none,
      );
    });
  });
}
