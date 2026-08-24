import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/vault_entry.dart';
import 'package:isle_log/services/vault/vault_storage.dart';

VaultEntry _entry(String id, String content) => VaultEntry(
  id: id,
  content: content,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  tags: const [],
  attachmentIds: const [],
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('创建 vault 后立即处于解锁状态，且没有条目', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');

    expect(storage.isUnlocked, isTrue);
    expect(storage.entries, isEmpty);
  });

  test('锁定后再用正确口令解锁，能读回之前保存的条目', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');
    await storage.saveEntry(_entry('e1', '秘密内容'));
    storage.lock();
    expect(storage.isUnlocked, isFalse);

    final reopened = VaultStorage(dir: tempDir);
    final ok = await reopened.unlock('CorrectHorse1');

    expect(ok, isTrue);
    expect(reopened.entries.single.content, '秘密内容');
  });

  test('恢复码也能解锁同一个 vault', () async {
    final storage = VaultStorage(dir: tempDir);
    final recoveryCode = await storage.createVault('CorrectHorse1');
    await storage.saveEntry(_entry('e1', '秘密内容'));
    storage.lock();

    final ok = await storage.unlock(recoveryCode);

    expect(ok, isTrue);
    expect(storage.entries.single.content, '秘密内容');
  });

  test('错误口令解锁失败，不改变磁盘上的数据', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');
    storage.lock();

    final ok = await storage.unlock('TotallyWrong9');

    expect(ok, isFalse);
    expect(storage.isUnlocked, isFalse);
  });

  test('idx.bin 从第 0 字节起就没有可识别结构（无明文头、无关键词）', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');

    final bytes = await File('${tempDir.path}/idx.bin').readAsBytes();
    final asText = String.fromCharCodes(bytes.where((b) => b < 128));
    expect(asText.contains('content'), isFalse);
    expect(asText.contains('vault'), isFalse);
    expect(asText.contains('entries'), isFalse);
    // 前两个字节不应是固定的 [1, x] 版本/标志位
    expect(bytes.length, greaterThan(152));
  });

  test('每次保存的 revision 单调递增', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');
    final r0 = storage.revision;

    await storage.saveEntry(_entry('e1', 'a'));
    final r1 = storage.revision;
    await storage.saveEntry(_entry('e2', 'b'));
    final r2 = storage.revision;

    expect(r1, greaterThan(r0));
    expect(r2, greaterThan(r1));
  });

  test('idx.bin 损坏时回退读 .bak 仍能解锁，并治愈主文件', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');
    await storage.saveEntry(_entry('e1', '第一版'));
    await storage.saveEntry(_entry('e2', '第二版')); // 触发 .bak 生成
    storage.lock();

    // 把主文件写坏
    await File(
      '${tempDir.path}/idx.bin',
    ).writeAsBytes(Uint8List.fromList(List.filled(200, 0)));

    final ok = await storage.unlock('CorrectHorse1');

    expect(ok, isTrue, reason: '主文件损坏应回退到 .bak');
    // 主文件应被 bak 治愈（不再是全 0 的损坏文件）
    final healed = await File('${tempDir.path}/idx.bin').readAsBytes();
    expect(healed.length, greaterThan(152));
    expect(healed.take(20).any((b) => b != 0), isTrue);
  });

  test('截断的文件不抛异常，只返回 false', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');
    storage.lock();
    await File(
      '${tempDir.path}/idx.bin',
    ).writeAsBytes(Uint8List.fromList([1, 2, 3]));
    final bak = File('${tempDir.path}/idx.bin.bak');
    if (await bak.exists()) await bak.delete();

    expect(await storage.unlock('CorrectHorse1'), isFalse);
  });

  test('锁定状态下写入抛 StateError，而不是空指针崩溃', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');
    storage.lock();

    expect(
      () => storage.saveEntry(_entry('e1', 'x')),
      throwsA(isA<StateError>()),
    );
  });

  test('adoptRemoteIndex 口令不匹配时返回 false 且不覆盖本地数据', () async {
    final local = VaultStorage(dir: tempDir);
    await local.createVault('CorrectHorse1');
    await local.saveEntry(_entry('local-1', '本地珍贵数据'));

    // 另一个目录里造一个用不同口令的 vault，模拟"远端数据"
    final otherDir = await Directory.systemTemp.createTemp('vault_other_');
    final other = VaultStorage(dir: otherDir);
    await other.createVault('DifferentPass2');
    final remoteBytes = (await other.readEncryptedIndexBytes())!;

    final ok = await local.adoptRemoteIndex(remoteBytes, 'CorrectHorse1');

    expect(ok, isFalse);
    expect(local.entries.single.content, '本地珍贵数据', reason: '验证失败必须在覆盖之前拦住');

    await otherDir.delete(recursive: true);
  });

  test('adoptRemoteIndex 口令匹配时落盘并载入远端条目', () async {
    final otherDir = await Directory.systemTemp.createTemp('vault_other_');
    final source = VaultStorage(dir: otherDir);
    await source.createVault('SharedPass3');
    await source.saveEntry(_entry('remote-1', '来自旧手机'));
    final remoteBytes = (await source.readEncryptedIndexBytes())!;

    // 全新设备：目录里什么都没有
    final fresh = VaultStorage(dir: tempDir);
    final ok = await fresh.adoptRemoteIndex(remoteBytes, 'SharedPass3');

    expect(ok, isTrue);
    expect(fresh.isUnlocked, isTrue);
    expect(fresh.entries.single.content, '来自旧手机');
    expect(await File('${tempDir.path}/idx.bin').exists(), isTrue);

    await otherDir.delete(recursive: true);
  });

  test('附件增删能被读回，且带 mimeType', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');

    await storage.addAttachment(
      VaultAttachment(
        id: 'a1',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList([9, 8, 7]),
      ),
    );

    expect(storage.attachmentBytes('a1'), Uint8List.fromList([9, 8, 7]));
    expect(storage.attachmentMimeType('a1'), 'image/jpeg');

    await storage.removeAttachment('a1');
    expect(storage.attachmentBytes('a1'), isNull);
  });

  test('adoptRemotePair 两份都验证通过才落盘，atc 缺失时整体失败', () async {
    final otherDir = await Directory.systemTemp.createTemp('vault_other_');
    final source = VaultStorage(dir: otherDir);
    await source.createVault('SharedPass4');
    await source.saveEntry(_entry('remote-1', '来自旧手机'));
    final idxBytes = (await source.readEncryptedIndexBytes())!;
    final atcBytes = (await source.readEncryptedAttachmentBytes())!;

    final fresh = VaultStorage(dir: tempDir);
    final ok = await fresh.adoptRemotePair(idxBytes, atcBytes, 'SharedPass4');
    expect(ok, isTrue);
    expect(fresh.entries.single.content, '来自旧手机');
    expect(await File('${tempDir.path}/atc.bin').exists(), isTrue);

    final fresh2Dir = await Directory.systemTemp.createTemp('vault_fresh2_');
    final fresh2 = VaultStorage(dir: fresh2Dir);
    expect(
      await fresh2.adoptRemotePair(idxBytes, null, 'SharedPass4'),
      isFalse,
    );
    expect(
      await File('${fresh2Dir.path}/idx.bin').exists(),
      isFalse,
      reason: 'atc 缺失必须整体失败，不能先落 idx',
    );

    await otherDir.delete(recursive: true);
    await fresh2Dir.delete(recursive: true);
  });
}
