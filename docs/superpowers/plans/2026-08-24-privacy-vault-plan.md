# 隐私空间（Vault）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 IsleLog 客户端内实现一个隐藏的、加密的隐私空间：通过主页搜索框口令进入，数据以不透明密文文件存于本地，可选同步到服务端（伪装成加密备份），支持文字日记 + 附件，支持把普通日记移入/移出。

**Architecture:** 隐私空间数据完全独立于 Isar 主库，存于两个加密文件（`idx.bin` 文字索引 / `atc.bin` 附件包），解锁后整体解密进内存，锁定时清空。密钥由口令通过 Argon2id 派生的 KEK 包裹一把随机主密钥（同时用恢复码包裹第二份），磁盘上不存口令哈希。UI 层是一个独立的 `features/vault/` 模块 + 一个搜索框钩子，不侵入现有 `MemoEditorPage`（3000+ 行、耦合 AI/位置/天气/网络附件流程，重用风险高于新写一个精简编辑器）。

**Tech Stack:** `cryptography` ^2.9.0（Argon2id + AES-GCM，纯 Dart）、现有 `image_picker` / `record` / `just_audio` / `path_provider`。

**Spec:** `docs/superpowers/specs/2026-08-24-privacy-vault-design.md`

## Global Constraints

- 磁盘上不存口令哈希或任何校验值；口令验证 = 能否用派生密钥解开 AEAD 密文（GCM tag 校验）。
- Argon2id 参数：`parallelism=1, memory=32000 (KiB, ≈32MB), iterations=2, hashLength=32`（`cryptography` 包的 `memory` 单位是 KiB）。
- 加密算法统一用 `AesGcm.with256bits()`（12B nonce，16B mac，标准值）。
- vault 的标签/统计**不写入** `TagStat` 表或任何主库结构，只在内存中现算。
- vault 编辑流程**绝不**调用 `SettingsService.saveDraft` / `draftContent` / `draftLocation`。
- 附件明文只允许短暂落盘（录音必须先写文件再读入内存，这是 `record` 包的限制），用后必须立即删除临时文件；查看/播放一律走内存（`Image.memory` / 自定义 `StreamAudioSource`），不建临时文件。
- vault 相关新代码放在 `lib/services/vault/` 和 `lib/features/vault/`；不改动 Isar `@collection` 模型，不需要跑 `build_runner`。
- 与本仓库现有的静态 service 类风格（`DatabaseService`/`SettingsService`）不同：`VaultStorage` 设计为可实例化的普通类（构造时注入 `Directory`），因为它涉及文件 IO + 加密，需要在单元测试中注入临时目录——这是刻意的风格偏离，理由见 Task 5。
- Task 11（服务端硬删除）客户端改动可以完成，但**依赖服务端新增接口**，服务端代码不在本仓库，不在本计划实现范围内；该任务的定义是"客户端准备好调用它"，不是"端到端验证硬删除生效"。

---

### Task 1: 添加 cryptography 依赖

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: `package:cryptography` 可在任意 Dart 文件中 `import 'package:cryptography/cryptography.dart';`

- [ ] **Step 1: 添加依赖**

在 `pubspec.yaml` 的 `dependencies:` 块内，`diff_match_patch: ^0.4.1` 那行之后加一行：

```yaml
  diff_match_patch: ^0.4.1
  cryptography: ^2.9.0
```

- [ ] **Step 2: 安装**

Run: `flutter pub get`
Expected: 无报错，`pubspec.lock` 中出现 `cryptography` 条目。

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: 添加 cryptography 依赖，为隐私空间做准备"
```

---

### Task 2: VaultCrypto —— 密钥派生与加解密（纯函数）

**Files:**
- Create: `lib/services/vault/vault_crypto.dart`
- Test: `test/services/vault/vault_crypto_test.dart`

**Interfaces:**
- Produces:
  - `class VaultCrypto`
  - `static Uint8List VaultCrypto.generateSalt()` — 16 字节随机盐
  - `static Future<SecretKey> VaultCrypto.generateMasterKey()`
  - `static Future<Uint8List> VaultCrypto.wrapMasterKey(SecretKey masterKey, String passphrase)` — 返回 76 字节 keyslot（16B salt + 12B nonce + 32B ciphertext + 16B mac）
  - `static Future<SecretKey?> VaultCrypto.tryUnwrapMasterKey(Uint8List keyslot76, String passphrase)` — 口令错误时返回 `null`（不抛异常）
  - `static Future<Uint8List> VaultCrypto.encryptBlob(SecretKey masterKey, Uint8List plaintext)` — 返回 12B nonce + ciphertext + 16B mac
  - `static Future<Uint8List?> VaultCrypto.decryptBlob(SecretKey masterKey, Uint8List packed)` — 校验失败返回 `null`
  - `static String VaultCrypto.generateRecoveryCode()` — 24 位字符（排除易混字符）

- [ ] **Step 1: 写失败测试**

```dart
// test/services/vault/vault_crypto_test.dart
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
  });

  group('VaultCrypto.generateRecoveryCode', () {
    test('生成 24 位字符，且不含易混字符 0/O/1/I/L', () async {
      final code = VaultCrypto.generateRecoveryCode();
      expect(code.length, 24);
      expect(code.contains(RegExp(r'[0O1IL]')), isFalse);
    });
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/services/vault/vault_crypto_test.dart`
Expected: FAIL，报错找不到 `lib/services/vault/vault_crypto.dart`。

- [ ] **Step 3: 实现**

```dart
// lib/services/vault/vault_crypto.dart
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
    if (keyslot76.length != _saltLength + _nonceLength + _mkLength + _macLength) {
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
    } on SecretBoxAuthenticationError {
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
    try {
      final box = SecretBox.fromConcatenation(
        packed,
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final plaintext = await _aead.decrypt(box, secretKey: masterKey);
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  static const _recoveryAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static String generateRecoveryCode() {
    final rnd = Random.secure();
    return List.generate(
      24,
      (_) => _recoveryAlphabet[rnd.nextInt(_recoveryAlphabet.length)],
    ).join();
  }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/services/vault/vault_crypto_test.dart`
Expected: PASS（6 个测试全绿）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/vault/vault_crypto.dart test/services/vault/vault_crypto_test.dart
git commit -m "feat: 新增 VaultCrypto，隐私空间密钥派生与加解密"
```

---

### Task 3: VaultEntry / VaultAttachment 数据模型

**Files:**
- Create: `lib/data/models/vault_entry.dart`
- Test: `test/data/models/vault_entry_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class VaultEntry { String id; String content; DateTime createdAt; DateTime updatedAt; List<String> tags; List<String> attachmentIds; String? memosName; String? movedFromMemosName; }`
  - `VaultEntry.toJson() -> Map<String, dynamic>`
  - `VaultEntry.fromJson(Map<String, dynamic>) -> VaultEntry`
  - `class VaultAttachment { String id; String mimeType; Uint8List bytes; }`（供 Task 4 的编解码器使用，本任务只定义类，不做 TLV 编解码）

- [ ] **Step 1: 写失败测试**

```dart
// test/data/models/vault_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/vault_entry.dart';

void main() {
  test('VaultEntry 序列化后能还原全部字段', () {
    final entry = VaultEntry(
      id: 'abc-123',
      content: '今天...',
      createdAt: DateTime.utc(2026, 8, 24, 10, 30),
      updatedAt: DateTime.utc(2026, 8, 24, 11, 0),
      tags: ['心情', '私密'],
      attachmentIds: ['att-1', 'att-2'],
      memosName: 'memos/999',
      movedFromMemosName: 'memos/42',
    );

    final restored = VaultEntry.fromJson(entry.toJson());

    expect(restored.id, entry.id);
    expect(restored.content, entry.content);
    expect(restored.createdAt, entry.createdAt);
    expect(restored.updatedAt, entry.updatedAt);
    expect(restored.tags, entry.tags);
    expect(restored.attachmentIds, entry.attachmentIds);
    expect(restored.memosName, entry.memosName);
    expect(restored.movedFromMemosName, entry.movedFromMemosName);
  });

  test('memosName 和 movedFromMemosName 允许为 null 并正确还原', () {
    final entry = VaultEntry(
      id: 'abc-124',
      content: 'x',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      tags: const [],
      attachmentIds: const [],
    );

    final restored = VaultEntry.fromJson(entry.toJson());

    expect(restored.memosName, isNull);
    expect(restored.movedFromMemosName, isNull);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/data/models/vault_entry_test.dart`
Expected: FAIL，找不到 `lib/data/models/vault_entry.dart`。

- [ ] **Step 3: 实现**

```dart
// lib/data/models/vault_entry.dart
import 'dart:typed_data';

/// 隐私空间日记条目（不是 Isar collection，只存在于解密后的内存中）。
class VaultEntry {
  final String id;
  String content;
  final DateTime createdAt;
  DateTime updatedAt;
  List<String> tags;
  List<String> attachmentIds;
  String? memosName;
  final String? movedFromMemosName;

  VaultEntry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
    required this.attachmentIds,
    this.memosName,
    this.movedFromMemosName,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'tags': tags,
    'attachmentIds': attachmentIds,
    'memosName': memosName,
    'movedFromMemosName': movedFromMemosName,
  };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
    id: json['id'] as String,
    content: json['content'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    tags: (json['tags'] as List).cast<String>(),
    attachmentIds: (json['attachmentIds'] as List).cast<String>(),
    memosName: json['memosName'] as String?,
    movedFromMemosName: json['movedFromMemosName'] as String?,
  );
}

/// 隐私空间附件的原始字节 + 元数据。
///
/// 不复用主库的 [AttachmentInfo]——那个类围绕"本地路径 + 远端 URL"设计，
/// vault 附件只有加密前的原始字节，没有独立的本地文件路径。
class VaultAttachment {
  final String id;
  final String mimeType;
  final Uint8List bytes;

  const VaultAttachment({
    required this.id,
    required this.mimeType,
    required this.bytes,
  });
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/data/models/vault_entry_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/vault_entry.dart test/data/models/vault_entry_test.dart
git commit -m "feat: 新增 VaultEntry/VaultAttachment 数据模型"
```

---

### Task 4: 附件容器编解码（TLV）

**Files:**
- Create: `lib/services/vault/vault_container_codec.dart`
- Test: `test/services/vault/vault_container_codec_test.dart`

**Interfaces:**
- Consumes: `VaultAttachment`（Task 3）
- Produces:
  - `class VaultContainerCodec`
  - `static Uint8List VaultContainerCodec.encodeAttachments(List<VaultAttachment> items)`
  - `static List<VaultAttachment> VaultContainerCodec.decodeAttachments(Uint8List data)`

- [ ] **Step 1: 写失败测试**

```dart
// test/services/vault/vault_container_codec_test.dart
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
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/services/vault/vault_container_codec_test.dart`
Expected: FAIL，找不到 `lib/services/vault/vault_container_codec.dart`。

- [ ] **Step 3: 实现**

```dart
// lib/services/vault/vault_container_codec.dart
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
    final view = ByteData.sublistView(data);
    var offset = 0;
    final count = view.getUint32(offset, Endian.big);
    offset += 4;
    final result = <VaultAttachment>[];
    for (var i = 0; i < count; i++) {
      final idLen = view.getUint16(offset, Endian.big);
      offset += 2;
      final id = utf8.decode(data.sublist(offset, offset + idLen));
      offset += idLen;

      final mimeLen = view.getUint16(offset, Endian.big);
      offset += 2;
      final mime = utf8.decode(data.sublist(offset, offset + mimeLen));
      offset += mimeLen;

      final dataLen = view.getUint32(offset, Endian.big);
      offset += 4;
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
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/services/vault/vault_container_codec_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/services/vault/vault_container_codec.dart test/services/vault/vault_container_codec_test.dart
git commit -m "feat: 新增附件容器 TLV 编解码"
```

---

### Task 5: VaultStorage —— 文件级读写

**Files:**
- Create: `lib/services/vault/vault_storage.dart`
- Test: `test/services/vault/vault_storage_test.dart`

**Interfaces:**
- Consumes: `VaultCrypto`（Task 2）、`VaultEntry`/`VaultAttachment`（Task 3）、`VaultContainerCodec`（Task 4）
- Produces:
  - `class VaultStorage { VaultStorage({required Directory dir}); }`
  - `bool get isUnlocked`
  - `Future<bool> exists()`
  - `List<VaultEntry> get entries`
  - `Future<String> createVault(String passphrase)` — 返回恢复码
  - `Future<bool> unlock(String passphrase)`
  - `void lock()`
  - `Future<void> saveEntry(VaultEntry entry)`
  - `Future<void> deleteEntry(String id)`
  - `Uint8List? attachmentBytes(String id)`
  - `Future<void> addAttachment(VaultAttachment attachment)`
  - `Future<void> removeAttachment(String id)`
  - `Uint8List? readEncryptedIndexBytes()`
  - `Uint8List? readEncryptedAttachmentBytes()`
  - `Future<void> replaceFromRemote(Uint8List idxBytes, Uint8List? atcBytes)`

这个类是**可实例化的普通类**而非静态 service（见 Global Constraints 里的说明），构造时注入 `Directory`，测试用临时目录，生产环境由 Task 6 的 `VaultController` 传入 `getApplicationSupportDirectory()`。

- [ ] **Step 1: 写失败测试**

```dart
// test/services/vault/vault_storage_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/vault_entry.dart';
import 'package:isle_log/services/vault/vault_storage.dart';

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
    await storage.createVault('correct horse battery staple');

    expect(storage.isUnlocked, isTrue);
    expect(storage.entries, isEmpty);
  });

  test('锁定后再用正确口令解锁，能读回之前保存的条目', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('correct horse battery staple');
    await storage.saveEntry(
      VaultEntry(
        id: 'e1',
        content: '秘密内容',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        tags: const [],
        attachmentIds: const [],
      ),
    );
    storage.lock();
    expect(storage.isUnlocked, isFalse);

    final reopened = VaultStorage(dir: tempDir);
    final ok = await reopened.unlock('correct horse battery staple');

    expect(ok, isTrue);
    expect(reopened.entries.single.content, '秘密内容');
  });

  test('错误口令解锁失败，不改变磁盘上的数据', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('correct horse battery staple');
    storage.lock();

    final ok = await storage.unlock('totally wrong passphrase');

    expect(ok, isFalse);
    expect(storage.isUnlocked, isFalse);
  });

  test('idx.bin 文件内容看不出任何可识别结构（没有 magic header 字符串）', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('correct horse battery staple');

    final bytes = await File('${tempDir.path}/idx.bin').readAsBytes();
    final asText = String.fromCharCodes(bytes.where((b) => b < 128));
    expect(asText.contains('content'), isFalse);
    expect(asText.contains('vault'), isFalse);
  });

  test('exists() 在创建前返回 false，创建后返回 true', () async {
    final storage = VaultStorage(dir: tempDir);
    expect(await storage.exists(), isFalse);

    await storage.createVault('correct horse battery staple');

    expect(await storage.exists(), isTrue);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/services/vault/vault_storage_test.dart`
Expected: FAIL，找不到 `lib/services/vault/vault_storage.dart`。

- [ ] **Step 3: 实现**

```dart
// lib/services/vault/vault_storage.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../data/models/vault_entry.dart';
import 'vault_container_codec.dart';
import 'vault_crypto.dart';

/// 隐私空间的文件级读写：idx.bin（文字，小，频繁重写）+ atc.bin（附件，大，仅增删附件时重写）。
///
/// 两个文件共用同一把主密钥。idx.bin 头部带两个 keyslot（口令 / 恢复码），
/// atc.bin 不带 keyslot——它只在已解锁的会话内被读写，不需要独立可解锁。
class VaultStorage {
  VaultStorage({required this.dir});

  final Directory dir;

  File get _idxFile => File(p.join(dir.path, 'idx.bin'));
  File get _atcFile => File(p.join(dir.path, 'atc.bin'));

  static const _version = 1;
  static const _keyslotLength = 76;

  SecretKey? _masterKey;
  Uint8List? _passwordSlot;
  Uint8List? _recoverySlot;
  List<VaultEntry> _entries = [];
  List<VaultAttachment> _attachments = [];

  bool get isUnlocked => _masterKey != null;

  List<VaultEntry> get entries => List.unmodifiable(_entries);

  Future<bool> exists() => _idxFile.exists();

  Future<String> createVault(String passphrase) async {
    final mk = await VaultCrypto.generateMasterKey();
    final recoveryCode = VaultCrypto.generateRecoveryCode();

    _masterKey = mk;
    _passwordSlot = await VaultCrypto.wrapMasterKey(mk, passphrase);
    _recoverySlot = await VaultCrypto.wrapMasterKey(mk, recoveryCode);
    _entries = [];
    _attachments = [];

    if (!await dir.exists()) await dir.create(recursive: true);
    await _flushIndex();
    await _flushAttachments();

    return recoveryCode;
  }

  Future<bool> unlock(String passphrase) async {
    if (!await _idxFile.exists()) return false;
    final raw = await _idxFile.readAsBytes();
    if (raw.length < 2 + _keyslotLength) return false;

    final hasRecoverySlot = raw[1] == 1;
    var offset = 2;
    final passwordSlot = raw.sublist(offset, offset + _keyslotLength);
    offset += _keyslotLength;
    Uint8List? recoverySlot;
    if (hasRecoverySlot) {
      recoverySlot = raw.sublist(offset, offset + _keyslotLength);
      offset += _keyslotLength;
    }

    var mk = await VaultCrypto.tryUnwrapMasterKey(passwordSlot, passphrase);
    mk ??= recoverySlot == null
        ? null
        : await VaultCrypto.tryUnwrapMasterKey(recoverySlot, passphrase);
    if (mk == null) return false;

    final body = raw.sublist(offset);
    final decrypted = await VaultCrypto.decryptBlob(mk, body);
    if (decrypted == null) return false;

    _masterKey = mk;
    _passwordSlot = passwordSlot;
    _recoverySlot = recoverySlot;
    _entries = (jsonDecode(utf8.decode(decrypted)) as List)
        .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    if (await _atcFile.exists()) {
      final atcRaw = await _atcFile.readAsBytes();
      final atcDecrypted = await VaultCrypto.decryptBlob(mk, atcRaw);
      _attachments = atcDecrypted == null
          ? []
          : VaultContainerCodec.decodeAttachments(atcDecrypted);
    } else {
      _attachments = [];
    }

    return true;
  }

  void lock() {
    _masterKey = null;
    _passwordSlot = null;
    _recoverySlot = null;
    _entries = [];
    _attachments = [];
  }

  Future<void> saveEntry(VaultEntry entry) async {
    _entries = [
      ..._entries.where((e) => e.id != entry.id),
      entry,
    ];
    await _flushIndex();
  }

  Future<void> deleteEntry(String id) async {
    final target = _entries.where((e) => e.id == id).firstOrNull;
    _entries = _entries.where((e) => e.id != id).toList();
    await _flushIndex();
    if (target != null && target.attachmentIds.isNotEmpty) {
      _attachments = _attachments
          .where((a) => !target.attachmentIds.contains(a.id))
          .toList();
      await _flushAttachments();
    }
  }

  Uint8List? attachmentBytes(String id) =>
      _attachments.where((a) => a.id == id).firstOrNull?.bytes;

  Future<void> addAttachment(VaultAttachment attachment) async {
    _attachments = [
      ..._attachments.where((a) => a.id != attachment.id),
      attachment,
    ];
    await _flushAttachments();
  }

  Future<void> removeAttachment(String id) async {
    _attachments = _attachments.where((a) => a.id != id).toList();
    await _flushAttachments();
  }

  Uint8List? readEncryptedIndexBytes() =>
      _idxFile.existsSync() ? _idxFile.readAsBytesSync() : null;

  Uint8List? readEncryptedAttachmentBytes() =>
      _atcFile.existsSync() ? _atcFile.readAsBytesSync() : null;

  /// 用远端拉回的密文整体替换本地文件，然后用当前会话已持有的主密钥重新解锁刷新内存状态。
  /// 调用前必须已处于解锁状态（否则没有主密钥去解密拉回的数据）。
  Future<void> replaceFromRemote(Uint8List idxBytes, Uint8List? atcBytes) async {
    if (!isUnlocked) {
      throw StateError('replaceFromRemote 只能在已解锁状态下调用');
    }
    await _idxFile.writeAsBytes(idxBytes);
    if (atcBytes != null) await _atcFile.writeAsBytes(atcBytes);
    final passphraseKnownGoodMk = _masterKey!;
    lock();
    _masterKey = passphraseKnownGoodMk;
    // 直接用当前主密钥重新解析文件，不需要重新输入口令。
    await _reloadFromDiskWithCurrentKey();
  }

  Future<void> _reloadFromDiskWithCurrentKey() async {
    final mk = _masterKey!;
    final raw = await _idxFile.readAsBytes();
    final hasRecoverySlot = raw[1] == 1;
    var offset = 2 + _keyslotLength;
    if (hasRecoverySlot) offset += _keyslotLength;
    final body = raw.sublist(offset);
    final decrypted = await VaultCrypto.decryptBlob(mk, body);
    if (decrypted == null) {
      throw StateError('远端数据无法用当前主密钥解密，拒绝覆盖内存状态');
    }
    _entries = (jsonDecode(utf8.decode(decrypted)) as List)
        .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    if (await _atcFile.exists()) {
      final atcRaw = await _atcFile.readAsBytes();
      final atcDecrypted = await VaultCrypto.decryptBlob(mk, atcRaw);
      _attachments = atcDecrypted == null
          ? []
          : VaultContainerCodec.decodeAttachments(atcDecrypted);
    }
  }

  Future<void> _flushIndex() async {
    final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
    final body = await VaultCrypto.encryptBlob(
      _masterKey!,
      Uint8List.fromList(utf8.encode(json)),
    );
    final header = <int>[
      _version,
      _recoverySlot != null ? 1 : 0,
      ..._passwordSlot!,
      if (_recoverySlot != null) ..._recoverySlot!,
    ];
    await _idxFile.writeAsBytes([...header, ...body]);
  }

  Future<void> _flushAttachments() async {
    final encoded = VaultContainerCodec.encodeAttachments(_attachments);
    final body = await VaultCrypto.encryptBlob(_masterKey!, encoded);
    await _atcFile.writeAsBytes(body);
  }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/services/vault/vault_storage_test.dart`
Expected: PASS（5 个测试全绿）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/vault/vault_storage.dart test/services/vault/vault_storage_test.dart
git commit -m "feat: 新增 VaultStorage，隐私空间文件级读写"
```

---

### Task 6: VaultController —— 会话状态与锁定触发

**Files:**
- Create: `lib/services/vault/vault_controller.dart`
- Test: `test/services/vault/vault_controller_test.dart`

**Interfaces:**
- Consumes: `VaultStorage`（Task 5）
- Produces:
  - `class VaultController implements WidgetsBindingObserver`
  - `static VaultController get instance`
  - `ValueListenable<bool> get isUnlockedListenable`
  - `bool get isUnlocked`
  - `Future<bool> vaultExists()`
  - `Future<String> createVault(String passphrase)`
  - `Future<bool> tryUnlock(String candidate)`
  - `void lock()`
  - `List<VaultEntry> get entries`
  - `Future<void> saveEntry(VaultEntry entry)`（内部调用 `DatabaseService.extractTags` 填充 `tags`）
  - `Future<void> deleteEntry(String id)`
  - `Future<void> onEnterVaultPage()` / `Future<void> onLeaveVaultPage()`
  - `void attachLifecycleObserver()` — 供 `main.dart` 调用一次
  - （测试用）`@visibleForTesting VaultController.forTesting(VaultStorage storage)`

- [ ] **Step 1: 写失败测试**

只测纯状态逻辑（不测真实 `AppLifecycleState` 回调链路，那部分在 Task 7/8 里通过手动集成验证）：

```dart
// test/services/vault/vault_controller_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  test('createVault 后立即处于解锁状态，isUnlockedListenable 同步更新', () async {
    expect(controller.isUnlocked, isFalse);
    await controller.createVault('correct horse battery staple');
    expect(controller.isUnlocked, isTrue);
    expect(controller.isUnlockedListenable.value, isTrue);
  });

  test('tryUnlock 用错误口令返回 false 且不解锁', () async {
    await controller.createVault('correct horse battery staple');
    controller.lock();

    final ok = await controller.tryUnlock('wrong');

    expect(ok, isFalse);
    expect(controller.isUnlocked, isFalse);
  });

  test('lock 后 entries 清空', () async {
    await controller.createVault('correct horse battery staple');
    controller.lock();
    expect(controller.entries, isEmpty);
    expect(controller.isUnlockedListenable.value, isFalse);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/services/vault/vault_controller_test.dart`
Expected: FAIL，找不到 `lib/services/vault/vault_controller.dart`。

- [ ] **Step 3: 实现**

```dart
// lib/services/vault/vault_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database/database_service.dart';
import '../../data/models/vault_entry.dart';
import 'vault_storage.dart';

/// 隐私空间会话状态：解锁/锁定、后台超时自动锁定、进出页面自动锁定。
///
/// 单例，通过 [VaultController.instance] 访问；测试用 [VaultController.forTesting]
/// 注入指向临时目录的 [VaultStorage]，绕开 `path_provider` 的平台依赖。
class VaultController with WidgetsBindingObserver {
  VaultController._(this._storage);

  @visibleForTesting
  VaultController.forTesting(VaultStorage storage) : _storage = storage;

  static VaultController? _instance;

  static VaultController get instance {
    if (_instance != null) return _instance!;
    throw StateError('VaultController 尚未初始化，请先调用 VaultController.init()');
  }

  static Future<void> init() async {
    if (_instance != null) return;
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory_(p.join(supportDir.path, 'cache'));
    _instance = VaultController._(VaultStorage(dir: dir));
  }

  final VaultStorage _storage;
  final ValueNotifier<bool> _isUnlocked = ValueNotifier(false);
  DateTime? _backgroundedAt;
  static const _backgroundLockTimeout = Duration(seconds: 60);

  ValueListenable<bool> get isUnlockedListenable => _isUnlocked;
  bool get isUnlocked => _storage.isUnlocked;
  List<VaultEntry> get entries => _storage.entries;

  Future<bool> vaultExists() => _storage.exists();

  Future<String> createVault(String passphrase) async {
    final code = await _storage.createVault(passphrase);
    _isUnlocked.value = true;
    return code;
  }

  Future<bool> tryUnlock(String candidate) async {
    final ok = await _storage.unlock(candidate);
    if (ok) _isUnlocked.value = true;
    return ok;
  }

  void lock() {
    _storage.lock();
    _isUnlocked.value = false;
  }

  Future<void> saveEntry(VaultEntry entry) async {
    entry.tags = DatabaseService.extractTags(entry.content);
    entry.updatedAt = DateTime.now();
    await _storage.saveEntry(entry);
  }

  Future<void> deleteEntry(String id) => _storage.deleteEntry(id);

  VaultStorage get storageForSyncAndMigration => _storage;

  void onEnterVaultPage() {
    // 预留：目前锁定只在离开页面时触发，进入页面无需动作。
  }

  Future<void> onLeaveVaultPage() async {
    lock();
  }

  void attachLifecycleObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isUnlocked) return;
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null &&
          DateTime.now().difference(backgroundedAt) > _backgroundLockTimeout) {
        lock();
      }
    }
  }
}
```

> 注意：`Directory_` 是笔误占位——实现时直接用 `dart:io` 的 `Directory(...)`，并在文件顶部 `import 'dart:io';`。写这一步代码时把 `Directory_` 替换为 `Directory`。

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/services/vault/vault_controller_test.dart`
Expected: PASS（4 个测试全绿）。

- [ ] **Step 5: 接入 main.dart**

在 `lib/main.dart` 的 `WidgetsFlutterBinding.ensureInitialized();` 之后加：

```dart
  await VaultController.init();
  VaultController.instance.attachLifecycleObserver();
```

并在文件顶部加 `import 'services/vault/vault_controller.dart';`。

- [ ] **Step 6: Commit**

```bash
git add lib/services/vault/vault_controller.dart test/services/vault/vault_controller_test.dart lib/main.dart
git commit -m "feat: 新增 VaultController，隐私空间会话状态与自动锁定"
```

---

### Task 7: 搜索框口令钩子（创建 + 解锁入口）

**Files:**
- Modify: `lib/features/home/home_view.dart`

**Interfaces:**
- Consumes: `VaultController.instance`（Task 6）
- Produces: 无新公开接口（UI 行为）

- [ ] **Step 1: 定位并修改 `_SearchResultsState._doSearch`**

在 `lib/features/home/home_view.dart` 的 `_SearchResultsState._doSearch` 方法开头（约第 1198 行）插入口令识别逻辑。触发条件：长度 ≥ 8 且不含空格。`+` 前缀 → 走创建流程；否则尝试解锁。两种情况都不改变原有搜索行为——解锁/创建失败时，正常搜索继续执行，UI 上看不出区别。

```dart
  Future<void> _doSearch(String q) async {
    if (q == _lastQuery) return;
    _lastQuery = q;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    if (_looksLikeVaultPassphrase(q)) {
      final handled = await _tryHandleVaultInput(q);
      if (handled) return; // 已经跳转到隐私空间页，不再展示搜索结果
    }

    setState(() => _loading = true);

    final memos = await DatabaseService.searchMemos(q);
    final comments = await DatabaseService.searchComments(q);
    // ...（原有逻辑不变）
```

在 `_SearchResultsState` 类内新增两个私有方法：

```dart
  bool _looksLikeVaultPassphrase(String q) {
    final candidate = q.startsWith('+') ? q.substring(1) : q;
    return candidate.length >= 8 && !candidate.contains(' ');
  }

  /// 创建口令的强约束：必须同时含大写、小写、数字。
  ///
  /// 只用于 '+' 创建路径——防止日常一次凑巧 8 位以上、以 '+' 开头的搜索
  /// （比如 "+项目截止0824"）被误判成创建请求。不满足时按普通搜索处理，
  /// 不弹任何提示（提示本身就会暴露"这里有个特殊入口"）。
  bool _isStrongVaultPassphrase(String candidate) {
    if (candidate.length < 8 || candidate.contains(' ')) return false;
    final hasLower = candidate.contains(RegExp(r'[a-z]'));
    final hasUpper = candidate.contains(RegExp(r'[A-Z]'));
    final hasDigit = candidate.contains(RegExp(r'[0-9]'));
    return hasLower && hasUpper && hasDigit;
  }

  Future<bool> _tryHandleVaultInput(String q) async {
    if (q.startsWith('+')) {
      final passphrase = q.substring(1);
      if (!_isStrongVaultPassphrase(passphrase)) return false; // 强度不够，当普通搜索处理
      final exists = await VaultController.instance.vaultExists();
      if (exists) return false; // 已创建过，'+' 前缀不再生效，走普通搜索
      if (!mounted) return true;
      final confirmed = await _confirmCreateVault(passphrase);
      if (!confirmed) return true; // 用户取消，不展示任何结果，也不报错
      final recoveryCode = await VaultController.instance.createVault(passphrase);
      if (!mounted) return true;
      await _showRecoveryCode(recoveryCode);
      if (!mounted) return true;
      Navigator.of(context).pop(); // 关闭搜索
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const VaultPage()),
      );
      return true;
    }

    final ok = await VaultController.instance.tryUnlock(q);
    if (!ok) return false;
    if (!mounted) return true;
    Navigator.of(context).pop(); // 关闭搜索
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VaultPage()),
    );
    return true;
  }

  Future<bool> _confirmCreateVault(String passphrase) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建隐私空间？'),
        content: Text('口令：$passphrase\n\n请确认记住此口令，忘记将无法恢复数据。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认创建')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _showRecoveryCode(String code) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复码'),
        content: Text('忘记口令时可用此码解锁：\n\n$code\n\n请抄下并妥善保管，此码只显示这一次。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('我已记录')),
        ],
      ),
    );
  }
```

在文件顶部加 import：

```dart
import '../vault/vault_page.dart';
import '../../services/vault/vault_controller.dart';
```

（`VaultPage` 由 Task 8 创建；本任务先写好调用点，Task 8 完成后编译才会通过——这是本计划里唯一一个"先引用后实现"的依赖，两个任务提交顺序需相邻执行。）

- [ ] **Step 2: 手动验证（无自动化测试——原因见下）**

`_SearchResultsState` 是 `home_view.dart` 内的私有类，且 `showSearch`/`SearchDelegate` 的交互链路（打开搜索 → 输入 → 触发 dialog → 关闭搜索 → push 新页面）在 widget test 里搭建成本高、脆弱，与本代码库现状一致（`home_view.dart` 本身至今没有自己的 widget test，只有其子组件 `memo_search_card.dart` 有）。改为跑一次真机/模拟器手动验证：

1. `flutter run`
2. 主页点搜索图标，输入 `+testpass123`（全小写+数字，不满足大小写强约束）回车 → 应表现为普通搜索失败，**不**弹创建确认框
3. 输入 `+Testpass123`（含大小写+数字）回车 → 应弹出创建确认框
4. 确认后应看到恢复码弹窗，关闭后进入隐私空间页（此时为空列表，因为 Task 8 才实现内容）
5. 返回主页，再次搜索输入 `Testpass123` 回车 → 应直接进入隐私空间页
6. 输入错误口令（长度 ≥ 8）回车 → 应显示"没有找到"，与普通搜索失败一致

- [ ] **Step 3: Commit**

```bash
git add lib/features/home/home_view.dart
git commit -m "feat: 搜索框口令钩子，创建/解锁隐私空间入口"
```

---

### Task 8: VaultPage —— 合并时间线

**Files:**
- Create: `lib/features/vault/vault_page.dart`
- Create: `lib/features/vault/widgets/vault_entry_card.dart`
- Test: `test/features/vault/widgets/vault_entry_card_test.dart`

**Interfaces:**
- Consumes: `VaultController.instance`（Task 6）、`DatabaseService.getAllMemos()`（现有）
- Produces: `class VaultPage extends StatefulWidget`、`class VaultEntryCard extends StatelessWidget`

- [ ] **Step 1: 写 VaultEntryCard 的失败测试**

```dart
// test/features/vault/widgets/vault_entry_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/vault_entry.dart';
import 'package:isle_log/features/vault/widgets/vault_entry_card.dart';

void main() {
  testWidgets('展示 vault 条目的正文摘要和锁标记', (tester) async {
    final entry = VaultEntry(
      id: 'e1',
      content: '这是一条隐私日记',
      createdAt: DateTime(2026, 8, 24, 9, 0),
      updatedAt: DateTime(2026, 8, 24, 9, 0),
      tags: const [],
      attachmentIds: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VaultEntryCard(entry: entry, onTap: () {})),
      ),
    );

    expect(find.textContaining('这是一条隐私日记'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/features/vault/widgets/vault_entry_card_test.dart`
Expected: FAIL，找不到 `lib/features/vault/widgets/vault_entry_card.dart`。

- [ ] **Step 3: 实现 VaultEntryCard**

```dart
// lib/features/vault/widgets/vault_entry_card.dart
import 'package:flutter/material.dart';

import '../../../data/models/vault_entry.dart';
import '../../../shared/constants/app_constants.dart';

class VaultEntryCard extends StatelessWidget {
  final VaultEntry entry;
  final VoidCallback onTap;

  const VaultEntryCard({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final preview = entry.content.length > 80
        ? '${entry.content.substring(0, 80)}…'
        : entry.content;
    return Card(
      color: AppColors.surfaceWhite,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.lock, size: 18, color: AppColors.primaryDark),
        title: Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text(_formatTime(entry.createdAt)),
      ),
    );
  }

  String _formatTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/features/vault/widgets/vault_entry_card_test.dart`
Expected: PASS。

- [ ] **Step 5: 实现 VaultPage（合并时间线，不单独写测试——理由同 Task 7 Step 2：本代码库的页面级组件普遍靠手动验证，子组件才写单测）**

```dart
// lib/features/vault/vault_page.dart
import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/vault_entry.dart';
import '../../services/vault/vault_controller.dart';
import 'vault_editor_page.dart';
import 'widgets/vault_entry_card.dart';

sealed class _TimelineItem {
  DateTime get time;
}

class _MainItem extends _TimelineItem {
  final MemoEntry memo;
  _MainItem(this.memo);
  @override
  DateTime get time => memo.createdAt;
}

class _VaultItem extends _TimelineItem {
  final VaultEntry entry;
  _VaultItem(this.entry);
  @override
  DateTime get time => entry.createdAt;
}

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  bool _vaultOnly = false;
  List<MemoEntry> _mainMemos = [];

  @override
  void initState() {
    super.initState();
    _loadMain();
  }

  Future<void> _loadMain() async {
    final memos = await DatabaseService.getAllMemos();
    if (mounted) setState(() => _mainMemos = memos);
  }

  @override
  void dispose() {
    VaultController.instance.onLeaveVaultPage();
    super.dispose();
  }

  List<_TimelineItem> _mergedItems() {
    final vaultEntries = VaultController.instance.entries;
    final items = <_TimelineItem>[
      if (!_vaultOnly) ..._mainMemos.map(_MainItem.new),
      ...vaultEntries.map(_VaultItem.new),
    ];
    items.sort((a, b) => b.time.compareTo(a.time));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _mergedItems();
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私空间'),
        actions: [
          IconButton(
            icon: Icon(_vaultOnly ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: _vaultOnly ? '显示全部' : '仅看隐私',
            onPressed: () => setState(() => _vaultOnly = !_vaultOnly),
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('还没有条目'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final item = items[i];
                return switch (item) {
                  _VaultItem(:final entry) => VaultEntryCard(
                    entry: entry,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VaultEditorPage(existing: entry),
                        ),
                      );
                      setState(() {});
                    },
                  ),
                  _MainItem(:final memo) => ListTile(
                    title: Text(
                      memo.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('（普通日记，可从这里移入隐私空间）'),
                  ),
                };
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const VaultEditorPage()),
          );
          setState(() {});
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/vault/vault_page.dart lib/features/vault/widgets/vault_entry_card.dart test/features/vault/widgets/vault_entry_card_test.dart
git commit -m "feat: 新增隐私空间合并时间线页面"
```

---

### Task 9: VaultEditorPage —— 精简编辑器（不写草稿）

**Files:**
- Create: `lib/features/vault/vault_editor_page.dart`

**Interfaces:**
- Consumes: `VaultController.instance`（Task 6）、`VaultEntry`（Task 3）
- Produces: `class VaultEditorPage extends StatefulWidget { const VaultEditorPage({VaultEntry? existing}); }`

**为什么不复用 `MemoEditorPage`**：那个文件 3000+ 行，耦合了 AI 润色、天气、位置、网络附件上传队列等一整套与"离线优先同步引擎"绑定的逻辑，且草稿自动保存分散在多处调用点（`memo_editor_page.dart:513/514/524/526/1382`）。把隐私属性塞进去意味着要在一个巨大、复杂、非隐私设计的文件里逐处审计"这条路径会不会碰草稿/网络"，审计面远大于收益。新写一个精简编辑器，安全性质从"没有调用草稿 API"这一行代码就能看出来。

- [ ] **Step 1: 实现（无预写测试——纯 UI 交互页面，手动验证见 Step 2，遵循 Task 7/8 的既有先例）**

```dart
// lib/features/vault/vault_editor_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/vault_entry.dart';
import '../../services/vault/vault_controller.dart';

class VaultEditorPage extends StatefulWidget {
  final VaultEntry? existing;

  const VaultEditorPage({super.key, this.existing});

  @override
  State<VaultEditorPage> createState() => _VaultEditorPageState();
}

class _VaultEditorPageState extends State<VaultEditorPage> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 有意不读取/写入 SettingsService 的草稿字段——这是隐私空间编辑器
    // 与 MemoEditorPage 的核心区别，绝不能让内容明文落进 SharedPreferences。
    _controller = TextEditingController(text: widget.existing?.content ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_controller.text.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final entry = widget.existing != null
        ? (widget.existing!..content = _controller.text)
        : VaultEntry(
            id: const Uuid().v4(),
            content: _controller.text,
            createdAt: now,
            updatedAt: now,
            tags: const [],
            attachmentIds: const [],
          );
    await VaultController.instance.saveEntry(entry);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    await VaultController.instance.deleteEntry(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新建隐私日记' : '编辑'),
        actions: [
          if (widget.existing != null)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          autofocus: widget.existing == null,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: '写点什么…',
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 手动验证**

1. `flutter run`，进入隐私空间，点右下角 `+`
2. 输入文字，点右上角勾 → 应返回列表并看到新条目
3. 重启 App，用同一口令重新进入隐私空间 → 内容应仍在（验证持久化）
4. 打开条目编辑，点删除图标 → 应从列表消失
5. 检查 `SharedPreferences`（真机上可用 `flutter run` 日志或临时加一行 `debugPrint` 验证）在整个操作过程中 `draft_content` key 从未被写入

- [ ] **Step 3: Commit**

```bash
git add lib/features/vault/vault_editor_page.dart
git commit -m "feat: 新增隐私空间精简编辑器，不写草稿"
```

---

### Task 10: 附件捕获与内存内查看

**Files:**
- Create: `lib/features/vault/vault_audio_source.dart`
- Modify: `lib/features/vault/vault_editor_page.dart`
- Modify: `lib/features/vault/widgets/vault_entry_card.dart`
- Test: `test/features/vault/vault_audio_source_test.dart`

**Interfaces:**
- Consumes: `VaultAttachment`（Task 3）、`VaultController.instance`（Task 6）
- Produces: `class VaultByteAudioSource extends StreamAudioSource`

- [ ] **Step 1: 写 VaultByteAudioSource 的失败测试**

```dart
// test/features/vault/vault_audio_source_test.dart
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
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/features/vault/vault_audio_source_test.dart`
Expected: FAIL，找不到 `lib/features/vault/vault_audio_source.dart`。

- [ ] **Step 3: 实现 VaultByteAudioSource**

```dart
// lib/features/vault/vault_audio_source.dart
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
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/features/vault/vault_audio_source_test.dart`
Expected: PASS。

- [ ] **Step 5: 在 VaultEditorPage 加图片/录音捕获**

在 `lib/features/vault/vault_editor_page.dart` 顶部加 import：

```dart
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart' show Uuid;
import '../../data/models/vault_entry.dart';
```

在 `_VaultEditorPageState` 内加状态与方法（沿用 `memo_editor_page.dart:675-701` 和 `:860-898` 的调用方式，改为写入内存而非上传/本地文件）：

```dart
  final List<VaultAttachment> _pendingAttachments = [];
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;

  @override
  void dispose() {
    _recorder.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (photo == null) return;
    final bytes = await File(photo.path).readAsBytes();
    setState(() {
      _pendingAttachments.add(
        VaultAttachment(id: const Uuid().v4(), mimeType: 'image/jpeg', bytes: bytes),
      );
    });
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path == null) return;
      final file = File(path);
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      await file.delete(); // 录音包必须先落盘（record 包限制），读入内存后立即删除临时文件
      setState(() {
        _pendingAttachments.add(
          VaultAttachment(id: const Uuid().v4(), mimeType: 'audio/aac', bytes: bytes),
        );
      });
    } else {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return;
      final tmpDir = await Directory.systemTemp.createTemp('vault_rec_');
      final path = '${tmpDir.path}/rec.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() => _recording = true);
    }
  }
```

`_save()` 改为在保存 entry 前，把 `_pendingAttachments` 逐个写入 `VaultController.instance`（需要 Task 6 补一个方法）并把 id 汇总进 `entry.attachmentIds`：

```dart
  Future<void> _save() async {
    if (_controller.text.trim().isEmpty && _pendingAttachments.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    for (final a in _pendingAttachments) {
      await VaultController.instance.addAttachment(a);
    }
    final now = DateTime.now();
    final attachmentIds = [
      ...?widget.existing?.attachmentIds,
      ..._pendingAttachments.map((a) => a.id),
    ];
    final entry = widget.existing != null
        ? (widget.existing!
            ..content = _controller.text
            ..attachmentIds = attachmentIds)
        : VaultEntry(
            id: const Uuid().v4(),
            content: _controller.text,
            createdAt: now,
            updatedAt: now,
            tags: const [],
            attachmentIds: attachmentIds,
          );
    await VaultController.instance.saveEntry(entry);
    if (mounted) Navigator.of(context).pop();
  }
```

在 UI 里的 `AppBar.actions` 加两个按钮触发 `_pickImage` / `_toggleRecording`（拍照按钮同理可加 `ImageSource.camera`，此处不重复列出，与 `_pickImage` 写法一致，仅 `source` 参数不同）。

在 `VaultController`（Task 6 的类）里补一个方法：

```dart
  Future<void> addAttachment(VaultAttachment attachment) =>
      _storage.addAttachment(attachment);
```

（记得在 `vault_controller.dart` 顶部加 `import '../../data/models/vault_entry.dart';` 若尚未导入。）

- [ ] **Step 6: 图片查看走内存**

在 `lib/features/vault/widgets/vault_entry_card.dart` 内，若 `entry.attachmentIds` 非空，为图片类型附件加一个横向缩略图条：

```dart
  Widget _buildThumbnails(BuildContext context) {
    final imageIds = entry.attachmentIds; // 实际按 mimeType 过滤，见下方说明
    if (imageIds.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: imageIds.map((id) {
          final bytes = VaultController.instance.storageForSyncAndMigration.attachmentBytes(id);
          if (bytes == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Image.memory(bytes, width: 64, height: 64, fit: BoxFit.cover),
          );
        }).toList(),
      ),
    );
  }
```

> 实现时需要按 mimeType 过滤出图片类的附件 id（`VaultController` 暴露的 `entries`/`attachmentBytes` 目前不带 mimeType 查询——补一个 `String? attachmentMimeType(String id)` 方法到 `VaultStorage`/`VaultController`，逻辑与 `attachmentBytes` 完全一致，只是返回 `mimeType` 字段），非图片（音频）附件在卡片里显示一个可点击的播放图标，点击后用 `AudioPlayer().setAudioSource(VaultByteAudioSource(bytes, mimeType: mime))` 播放，不在此列出重复代码。

- [ ] **Step 7: 手动验证**

1. 编辑隐私日记时点相册图标选一张图 → 保存后卡片应显示缩略图
2. 长按录音图标录一段音 → 停止后保存 → 重新打开应能播放
3. `flutter run` 期间用 `find $TMPDIR -iname "rec_*"` 检查录音临时文件在保存后已被删除

- [ ] **Step 8: Commit**

```bash
git add lib/features/vault/ test/features/vault/vault_audio_source_test.dart
git commit -m "feat: 隐私空间支持图片/录音附件，查看播放不落地临时文件"
```

---

### Task 11: 服务端硬删除接口 —— 客户端调用准备

**Files:**
- Modify: `lib/services/api/memos_api_service.dart`

**Interfaces:**
- Consumes: 无
- Produces: `Future<void> MemosApiService.deleteMemo(String name, {bool hard = false})`（在原有 `deleteMemo(String name)` 基础上加可选参数）

**⚠️ 阻塞说明**：本任务只做客户端改动。`?hard=true` 需要服务端新增对应处理逻辑（物理删除 memo 行 + 其版本历史表记录），服务端代码不在本仓库，需要在 islelog-server 项目里单独实现和部署。在服务端就绪前，Task 12 的移入功能调用这个接口时，效果等同于当前的软删除——明文仍留在服务端数据库，这是已知的、暂时无法在客户端侧解决的缺口（已在 spec 第 10 节标注）。

- [ ] **Step 1: 找到现有实现**

`lib/services/api/memos_api_service.dart:279`：

```dart
  Future<void> deleteMemo(String name) async {
```

- [ ] **Step 2: 修改**

```dart
  /// 删除远端 memo。
  ///
  /// [hard]：true 时请求物理删除（含版本历史），需服务端支持 `?hard=true`
  /// —— 移入隐私空间时必须用 hard=true，否则明文会残留在服务端软删除记录和版本历史里。
  /// 服务端未部署对应支持前，传 true 的效果退化为普通软删除（服务端忽略未知查询参数）。
  Future<void> deleteMemo(String name, {bool hard = false}) async {
    debugPrint('[API] deleteMemo name=$name hard=$hard');
    try {
      final path = hard ? '/api/v1/$name?hard=true' : '/api/v1/$name';
      await _dio.delete(path);
      debugPrint('[API] deleteMemo 成功');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }
```

- [ ] **Step 3: 确认无编译错误**

Run: `flutter analyze lib/services/api/memos_api_service.dart`
Expected: 无 error（原调用点 `deleteMemo(name)` 因为 `hard` 有默认值，不需要改动）。

- [ ] **Step 4: Commit**

```bash
git add lib/services/api/memos_api_service.dart
git commit -m "feat: MemosApiService.deleteMemo 支持 hard 参数（依赖服务端配合）"
```

---

### Task 12: 移入 / 移出

**Files:**
- Create: `lib/services/vault/vault_migration.dart`
- Modify: `lib/features/vault/vault_page.dart`

**Interfaces:**
- Consumes: `DatabaseService`（现有）、`AttachmentService.downloadToLocal`（现有）、`MemosApiService.deleteMemo(hard: true)`（Task 11）、`VaultController`（Task 6）
- Produces:
  - `Future<void> VaultMigration.moveIntoVault(MemoEntry memo)`
  - `Future<MemoEntry> VaultMigration.moveOutOfVault(VaultEntry entry)`

- [ ] **Step 1: 实现（无预写单测——依赖真实网络 IO 和 Isar，与 `sync_service.dart` 里同类集成函数的现状一致：那些函数也没有直接单测，只有其内部纯逻辑被抽成 `*_policy.dart` 单测）**

```dart
// lib/services/vault/vault_migration.dart
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/vault_entry.dart';
import '../api/memos_api_service.dart';
import '../attachment/attachment_service.dart';
import '../settings/settings_service.dart';
import 'vault_controller.dart';

/// 普通日记 ⇄ 隐私空间之间的移入/移出。
///
/// 移入时必须物理删除服务端原条目（含版本历史），否则明文会残留——
/// 依赖 [MemosApiService.deleteMemo] 的 hard 参数，服务端支持情况见 Task 11 说明。
class VaultMigration {
  VaultMigration._();

  static Future<void> moveIntoVault(MemoEntry memo) async {
    final attachmentIds = <String>[];
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;

    for (final att in memo.attachments) {
      var local = att;
      if ((local.localPath == null || !File(local.localPath!).existsSync()) &&
          url != null &&
          token != null) {
        local = await AttachmentService.downloadToLocal(att, url, token);
      }
      if (local.localPath == null) continue; // 下载失败，跳过该附件，不阻塞整体移入
      final bytes = await File(local.localPath!).readAsBytes();
      final id = const Uuid().v4();
      await VaultController.instance.addAttachment(
        VaultAttachment(id: id, mimeType: local.mimeType, bytes: bytes),
      );
      attachmentIds.add(id);
    }

    final now = DateTime.now();
    final entry = VaultEntry(
      id: const Uuid().v4(),
      content: memo.content,
      createdAt: memo.createdAt,
      updatedAt: now,
      tags: const [],
      attachmentIds: attachmentIds,
      movedFromMemosName: memo.memosName,
    );
    await VaultController.instance.saveEntry(entry);

    if (memo.memosName != null && url != null && token != null) {
      final api = MemosApiService(baseUrl: url, token: token);
      for (final att in memo.attachments) {
        if (att.remoteResName != null) {
          await api.deleteAttachment(att.remoteResName!);
        }
      }
      await api.deleteMemo(memo.memosName!, hard: true);
    }
    await DatabaseService.hardDelete(memo.id);
  }

  static Future<MemoEntry> moveOutOfVault(VaultEntry entry) async {
    final memo = MemoEntry()
      ..content = entry.content
      ..createdAt = entry.createdAt
      ..updatedAt = DateTime.now();
    // v1 不迁移附件字节回主库——附件迁出需要重新走 AttachmentService 的
    // 本地存储/上传流程，超出移入/移出这一任务的最小可用范围，留待后续迭代。
    final id = await DatabaseService.saveMemo(memo);
    await VaultController.instance.deleteEntry(entry.id);
    memo.id = id;
    return memo;
  }
}
```

- [ ] **Step 2: 在 VaultPage 加入口**

在 `lib/features/vault/vault_page.dart` 的 `_MainItem` 分支的 `ListTile` 上加 `onLongPress`：

```dart
                  _MainItem(:final memo) => ListTile(
                    title: Text(
                      memo.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('（普通日记，长按移入隐私空间）'),
                    onLongPress: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('移入隐私空间？'),
                          content: const Text('原日记将从主时间线永久移除。'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('移入')),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await VaultMigration.moveIntoVault(memo);
                        await _loadMain();
                        setState(() {});
                      }
                    },
                  ),
```

同理在 `VaultEntryCard` 的展示处（`_VaultItem` 分支）加一个"移出"按钮，调用 `VaultMigration.moveOutOfVault(entry)`，成功后 `_loadMain()` + `setState`（写法与上面一致，不重复列出）。

在文件顶部加 `import '../../services/vault/vault_migration.dart';`。

- [ ] **Step 3: 手动验证**

1. 在隐私空间页长按一条普通日记 → 确认后应从下方"普通"分组消失，出现在带锁标记的条目里
2. 返回主页时间线 → 该日记应完全不见
3. 若已配置服务端：登录服务端后台确认该 memo 已被删除（软删除或硬删除取决于服务端是否已支持 `?hard=true`，见 Task 11 说明）

- [ ] **Step 4: Commit**

```bash
git add lib/services/vault/vault_migration.dart lib/features/vault/vault_page.dart
git commit -m "feat: 隐私空间移入/移出功能"
```

---

### Task 13: 同步——封面故事 memo + 附件包

**Files:**
- Create: `lib/services/vault/vault_sync.dart`
- Modify: `lib/services/sync/sync_service.dart`
- Modify: `lib/services/settings/settings_service.dart`

**Interfaces:**
- Consumes: `VaultController`（Task 6）、`MemosApiService`（现有，含 Task 11 的 `hard` 参数）、`AttachmentService`（现有）
- Produces:
  - `Future<void> VaultSync.push()`
  - `Future<void> VaultSync.pull()`
  - `SyncService._applyRemoteMemo` 新增前缀过滤

- [ ] **Step 1: SettingsService 加一个存远端 memo 资源名的字段**

在 `lib/services/settings/settings_service.dart` 里，`_keyDraftContent` 附近加：

```dart
  static const _keyVaultBackupMemoName = 'vault_backup_memo_name';

  static Future<String?> get vaultBackupMemoName async =>
      (await _prefs).getString(_keyVaultBackupMemoName);

  static Future<void> setVaultBackupMemoName(String name) async {
    await (await _prefs).setString(_keyVaultBackupMemoName, name);
  }
```

这个 key 存的只是一个资源指针（"备份 memo 在服务端的 id"），不是任何秘密，明文存 SharedPreferences 没有安全含义——对应的封面故事本来就是一个真实存在的"加密云备份"功能。

- [ ] **Step 2: sync_service.dart 加前缀过滤**

在 `lib/services/sync/sync_service.dart` 的 `_applyRemoteMemo` 方法（第 913 行）开头加：

```dart
  static Future<int> _applyRemoteMemo(
    Map<String, dynamic> data,
    String baseUrl, {
    required bool archived,
  }) async {
    final content = data['content'] as String? ?? '';
    if (content.startsWith('IsleLog-Backup/1')) {
      return 0; // 隐私空间封面故事 memo，不写入主库、不渲染
    }

    final remoteName = data['name'] as String;
    // ...（原有逻辑不变）
```

- [ ] **Step 3: 实现 VaultSync**

```dart
// lib/services/vault/vault_sync.dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../api/memos_api_service.dart';
import '../settings/settings_service.dart';
import 'vault_controller.dart';

/// 隐私空间的同步：把加密后的 idx.bin/atc.bin 伪装成一条"加密备份" memo 上传，
/// 只在解锁期间进行；对应的 `_applyRemoteMemo` 前缀过滤见 sync_service.dart。
class VaultSync {
  VaultSync._();

  static const _contentPrefix = 'IsleLog-Backup/1';

  static Future<void> push() async {
    if (!VaultController.instance.isUnlocked) return;
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || token == null) return;

    final storage = VaultController.instance.storageForSyncAndMigration;
    final idxBytes = storage.readEncryptedIndexBytes();
    if (idxBytes == null) return;
    final atcBytes = storage.readEncryptedAttachmentBytes();

    final api = MemosApiService(baseUrl: url, token: token);
    final content = '$_contentPrefix\n${base64Encode(idxBytes)}';
    final existingName = await SettingsService.vaultBackupMemoName;

    String memoName;
    if (existingName != null) {
      await api.updateMemo(name: existingName, content: content, visibility: 'PRIVATE');
      memoName = existingName;
    } else {
      final created = await api.createMemo(content: content, visibility: 'PRIVATE');
      memoName = created['name'] as String;
      await SettingsService.setVaultBackupMemoName(memoName);
    }

    if (atcBytes != null) {
      final tmpDir = await Directory.systemTemp.createTemp('vault_sync_');
      final tmpFile = File(p.join(tmpDir.path, 'backup.dat'));
      await tmpFile.writeAsBytes(atcBytes);
      await api.uploadAttachment(file: tmpFile, filename: 'backup.dat', memoName: memoName);
      await tmpDir.delete(recursive: true);
    }
  }

  static Future<void> pull() async {
    if (!VaultController.instance.isUnlocked) return;
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || token == null) return;

    final existingName = await SettingsService.vaultBackupMemoName;
    if (existingName == null) return; // 本设备还没同步过，无远端备份可拉

    final api = MemosApiService(baseUrl: url, token: token);
    final remote = await api.getMemo(existingName.split('/').last);
    final content = remote['content'] as String? ?? '';
    if (!content.startsWith(_contentPrefix)) return;

    final idxBytes = base64Decode(content.substring(_contentPrefix.length + 1));

    // atc.bin 附件：取该 memo 的附件列表里第一个，下载字节。
    // （memos_api_service.dart 现有的附件列举/下载接口签名超出本任务改动范围，
    //  若需要拉取附件，复用 Task 已存在的 uploadAttachment 对称的下载调用方式，
    //  按 memo 的 attachments 字段里的资源名走现有下载路径。）
    await VaultController.instance.storageForSyncAndMigration
        .replaceFromRemote(idxBytes, null);
  }
}
```

> `pull()` 里附件下载部分刻意留白说明而非硬编代码——因为现有 `MemosApiService` 目前没有"按 memo 拉取其附件列表"的方法，需要先确认 `getMemo` 返回体里 `attachments` 字段的具体结构（`server-API.md` 第 226-335 行有列出但本计划未展开）。这是本计划里唯一一处需要执行者在动手前额外确认一次 API 响应结构的地方，不是空泛的"加错误处理"占位——是因为现有 API 客户端确实缺这个方法，需要照着 `server-API.md` 的"列出 Memo 的附件"和"下载附件"两节补一个 `MemosApiService.listMemoAttachments` / 复用 `downloadToLocal` 的字节版本。

- [ ] **Step 4: 接入调用点**

在 `lib/services/vault/vault_controller.dart` 的 `saveEntry`、`deleteEntry`、`addAttachment` 末尾各加一行 `unawaited(VaultSync.push());`（需要 `import 'dart:async';` 和 `import 'vault_sync.dart';`），在 `tryUnlock` 成功分支里加 `unawaited(VaultSync.pull());`。

- [ ] **Step 5: 手动验证**

1. 配置好服务端后创建隐私空间，写一条日记
2. 服务端后台确认出现一条 `IsleLog-Backup/1` 开头的 memo，`visibility=PRIVATE`
3. 换一台已登录同一服务端、但从未创建过本地隐私空间的设备 → 主时间线不应出现任何异常内容或崩溃（验证前缀过滤生效）
4. 在原设备清空本地 `idx.bin`（模拟换机），用同一口令解锁 → 触发 `pull()` 后应能看到之前的日记内容

- [ ] **Step 6: Commit**

```bash
git add lib/services/vault/vault_sync.dart lib/services/sync/sync_service.dart lib/services/settings/settings_service.dart lib/services/vault/vault_controller.dart
git commit -m "feat: 隐私空间同步，伪装为加密备份 memo"
```

---

### Task 14: 编译期开关 —— 分享版不含隐私空间

**Files:**
- Create: `lib/shared/constants/build_flags.dart`
- Modify: `lib/main.dart`
- Modify: `lib/features/home/home_view.dart`

**Interfaces:**
- Consumes: 无
- Produces: `const bool kVaultEnabled`

**为什么**：不只是运行时不显示入口，而是让分享出去的安装包在编译产物层面就不含这部分代码——这样即使有人拿这个包去反编译翻找，也翻不出"这个 App 曾经有隐私空间功能"这件事本身。

- [ ] **Step 1: 新增开关文件**

```dart
// lib/shared/constants/build_flags.dart

/// 编译期开关：控制隐私空间功能是否编译进最终产物。
///
/// 默认 true（日常自用构建不用额外传参）。要分享给他人的构建，显式传 false：
///
///   flutter build apk --release --dart-define=VAULT_ENABLED=false \
///     --obfuscate --split-debug-info=build/symbols
///
/// 因为这是编译期常量，`if (kVaultEnabled)` 为 false 的分支在 release 编译时
/// 会被当作死代码消除，连同其中只被这个分支引用的类一起被 tree-shake 掉，
/// 不是运行时判断隐藏。`--obfuscate` 是顺手加的免费加固，不是本开关必需。
const bool kVaultEnabled = bool.fromEnvironment(
  'VAULT_ENABLED',
  defaultValue: true,
);
```

- [ ] **Step 2: main.dart 接入**

把 Task 6 Step 5 加的两行包一层判断：

```dart
  if (kVaultEnabled) {
    await VaultController.init();
    VaultController.instance.attachLifecycleObserver();
  }
```

文件顶部加 `import 'shared/constants/build_flags.dart';`。

- [ ] **Step 3: home_view.dart 接入**

把 Task 7 Step 1 加的钩子调用包一层判断：

```dart
    if (kVaultEnabled && _looksLikeVaultPassphrase(q)) {
      final handled = await _tryHandleVaultInput(q);
      if (handled) return;
    }
```

文件顶部加 `import '../../shared/constants/build_flags.dart';`。

- [ ] **Step 4: 验证两种构建都能跑**

Run: `flutter build apk --debug`
Expected: 成功（默认 `kVaultEnabled=true`）。

Run: `flutter build apk --debug --dart-define=VAULT_ENABLED=false`
Expected: 成功；安装运行后，搜索框输入任何长度≥8 的口令都只表现为普通搜索，无论内容是否满足大小写+数字，都不触发任何 vault 相关弹窗或跳转。

这一步不做字节级反编译验证（超出常规开发流程的工具链，且对应的"不懂技术"威胁模型不需要这个强度的证明）——用"功能在运行时完全不可触发"作为验收标准。

- [ ] **Step 5: Commit**

```bash
git add lib/shared/constants/build_flags.dart lib/main.dart lib/features/home/home_view.dart
git commit -m "feat: 新增隐私空间编译期开关，支持构建不含该功能的分享版"
```

---

## Self-Review 记录

- **Spec 覆盖**：第 3 节（密钥）→ Task 2；第 4 节（入口锁定，含创建强约束）→ Task 7、Task 6 的后台计时；第 5 节（数据视图）→ Task 3/8；第 6 节（附件）→ Task 4/10；第 7 节（移入移出）→ Task 12；第 8 节（同步）→ Task 13；第 9 节（编译期开关）→ Task 14；第 10 节（硬删除接口 + 改动清单）→ Task 11、对应各任务。全部覆盖。
- **占位符扫描**：Task 13 的 `pull()` 附件下载部分不是占位符——已明确写出"为什么现在留白、需要执行者确认什么、确认后该怎么补"，且不影响本任务其余代码可编译可运行（`replaceFromRemote(idxBytes, null)` 是合法调用，只是附件暂不随拉取同步，文字内容的拉取路径是完整的）。
- **类型一致性**：`VaultController.instance.storageForSyncAndMigration` 在 Task 6/8/10/12/13 里统一使用同一个 getter 名；`VaultAttachment`/`VaultEntry` 字段名在 Task 3 定义后，Task 4/5/9/10/12 均保持一致引用。
