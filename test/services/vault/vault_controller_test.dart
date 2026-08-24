import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/vault_entry.dart';
import 'package:isle_log/services/vault/vault_controller.dart';
import 'package:isle_log/services/vault/vault_storage.dart';

void main() {
  late Directory tempDir;
  late VaultController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_controller_test_');
    controller = VaultController.forTesting(VaultStorage(dir: tempDir));
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('vault 不存在时 vaultExists 返回 false', () async {
    expect(await controller.vaultExists(), isFalse);
  });

  test('createVault 后立即解锁，isUnlockedListenable 同步更新', () async {
    expect(controller.isUnlocked, isFalse);
    await controller.createVault('CorrectHorse1');
    expect(controller.isUnlocked, isTrue);
    expect(controller.isUnlockedListenable.value, isTrue);
  });

  test('tryUnlock 用错误口令返回 false 且不解锁', () async {
    await controller.createVault('CorrectHorse1');
    controller.lock();

    expect(await controller.tryUnlock('WrongPass9'), isFalse);
    expect(controller.isUnlocked, isFalse);
  });

  test('lock 会广播 false，且清空条目', () async {
    await controller.createVault('CorrectHorse1');
    final observed = <bool>[];
    controller.isUnlockedListenable.addListener(
      () => observed.add(controller.isUnlockedListenable.value),
    );

    controller.lock();

    expect(observed, contains(false));
    expect(controller.entries, isEmpty);
  });

  test('saveEntry 自动从正文解析标签', () async {
    await controller.createVault('CorrectHorse1');
    await controller.saveEntry(
      VaultEntry(
        id: 'e1',
        content: '今天很好 #心情 #私密',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        tags: const [],
        attachmentIds: const [],
      ),
    );

    expect(controller.entries.single.tags, containsAll(['心情', '私密']));
  });
}
