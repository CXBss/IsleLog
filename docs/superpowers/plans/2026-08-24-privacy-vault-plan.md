# 隐私空间（Vault）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 IsleLog 客户端内实现一个隐藏的、加密的隐私空间：通过主页搜索框口令进入，数据以不透明密文文件存于本地，可选同步到服务端（伪装成加密备份），支持文字日记 + 附件，支持把普通日记移入/移出。

**Architecture:** 隐私空间数据完全独立于 Isar 主库，存于两个加密文件（`idx.bin` 文字索引 / `atc.bin` 附件包），解锁后整体解密进内存，锁定时清空。主密钥（MK）随机生成、属于 vault 而非设备，由口令和恢复码分别包裹成两个固定 keyslot 存在文件头，磁盘上不存口令哈希、不存任何明文头字节。UI 层是一个独立的 `features/vault/` 模块 + 一个只在回车提交时触发的搜索框钩子，不侵入现有 `MemoEditorPage`（3000+ 行、耦合 AI/位置/天气/网络附件流程，重用风险高于新写一个精简编辑器）。

**Tech Stack:** `cryptography` ^2.9.0（Argon2id + AES-GCM，纯 Dart）、现有 `image_picker` / `record` / `just_audio` / `path_provider`；截屏防护用自建 MethodChannel（Kotlin + Swift，不引第三方包）。

**Spec:** `docs/superpowers/specs/2026-08-24-privacy-vault-design.md`

## Global Constraints

- 磁盘上不存口令哈希或任何校验值；口令验证 = 能否用派生密钥解开 AEAD 密文（GCM tag 校验）。
- Argon2id 参数：`parallelism=1, memory=32000 (KiB, ≈32MB), iterations=2, hashLength=32`（`cryptography` 包的 `memory` 单位是 KiB）。
- 加密算法统一用 `AesGcm.with256bits()`（12B nonce，16B mac，标准值）。
- **文件头没有任何明文字节**：`idx.bin` 从第 0 字节起就是 `[76B 口令 keyslot][76B 恢复码 keyslot][加密 body]`。格式版本号、revision 等元信息全部放在加密后的 body JSON 里。恢复码因此是**必选**的（两个槽位恒定存在，文件布局在任何情况下完全一致）。
- **所有写盘必须原子**：写 `<target>.tmp` → `rename(<target> → <target>.bak)` → `rename(<target>.tmp → <target>)`。读取时 target 不存在或解不开就回退读 `.bak`。
- **解锁路径不允许异常冒泡**：长度不足、keyslot 截断、GCM 失败、JSON 非法、字段类型错——一律 catch 后返回 false/null，当作"这个口令打不开这个文件"。
- **从远端拿回的数据必须先在内存中验证解密成功，才能原子替换本地文件**，绝不先写盘后验证。
- 口令识别**只在 `SearchDelegate.buildResults`（回车提交）路径触发**，`buildSuggestions`（逐键输入）完全不触发；并缓存上一个已失败的候选串，避免重复跑 KDF。
- vault 的标签/统计**不写入** `TagStat` 表或任何主库结构，只在内存中现算。
- vault 编辑流程**绝不**调用 `SettingsService.saveDraft` / `draftContent` / `draftLocation`。
- 附件明文只允许短暂落盘（录音必须先写文件再读入内存，这是 `record` 包的限制；移出 vault 时也需临时文件过渡给 `AttachmentService`），用后必须立即删除；查看/播放一律走内存（`Image.memory` / 自定义 `StreamAudioSource`）。
- 存储目录为 `Application Support/blob/`。不用系统 Caches 目录（会被系统清空）；不调用平台 API 排除系统备份（理由见 spec 第 10 节）。
- 锁定只由 `AppLifecycleState.paused` 计时触发，**不**纳入 `inactive` / `hidden`（下拉通知栏、来电横幅会误触发）。任务切换器截图问题由 Task 15 的截屏防护独立解决，不靠调计时器。
- 存储层写方法禁止裸 `!` 断言，锁定状态下调用一律抛明确的 `StateError`。
- vault 相关新代码放在 `lib/services/vault/` 和 `lib/features/vault/`；不改动 Isar `@collection` 模型，不需要跑 `build_runner`。
- 与本仓库现有的静态 service 类风格（`DatabaseService`/`SettingsService`）不同：`VaultStorage` 设计为可实例化的普通类（构造时注入 `Directory`），因为它涉及文件 IO + 加密，需要在单元测试中注入临时目录——这是刻意的风格偏离，理由见 Task 5。
- Task 11（服务端硬删除）客户端改动可以完成，但**依赖服务端新增接口**，服务端代码不在本仓库，不在本计划实现范围内；该任务的定义是"客户端准备好调用它"，不是"端到端验证硬删除生效"。
- 同步模型是**单设备写 + 换机恢复**，不支持多设备并行编辑；`revision` 计数器只提供整体先后取舍，后推送的整体覆盖先推送的。

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
  - `VaultEntry.toJson() -> Map<String, dynamic>` / `VaultEntry.fromJson(Map<String, dynamic>)`
  - `class VaultBody { int version; int revision; List<VaultEntry> entries; }` + `toJson` / `fromJson`（加密 body 的顶层结构，承载版本号和同步用的 revision——这两个字段放进密文里，不放明文头）
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

  test('VaultBody 序列化后还原版本号、revision 和条目', () {
    final body = VaultBody(
      version: 1,
      revision: 17,
      entries: [
        VaultEntry(
          id: 'e1',
          content: 'x',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          tags: const [],
          attachmentIds: const [],
        ),
      ],
    );

    final restored = VaultBody.fromJson(body.toJson());

    expect(restored.version, 1);
    expect(restored.revision, 17);
    expect(restored.entries.single.id, 'e1');
  });

  test('VaultBody.fromJson 对缺失字段取默认值，不抛异常', () {
    final restored = VaultBody.fromJson(<String, dynamic>{});

    expect(restored.version, 1);
    expect(restored.revision, 0);
    expect(restored.entries, isEmpty);
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

/// 加密 body 的顶层结构。
///
/// 版本号和 revision 放在这里（密文内），不放明文文件头——
/// 明文头的固定字节会成为"这是个 vault 文件"的可识别特征。
class VaultBody {
  final int version;
  int revision;
  List<VaultEntry> entries;

  VaultBody({
    required this.version,
    required this.revision,
    required this.entries,
  });

  Map<String, dynamic> toJson() => {
    'v': version,
    'revision': revision,
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  /// 所有字段都取默认值兜底，供未来加字段时向前兼容。
  factory VaultBody.fromJson(Map<String, dynamic> json) => VaultBody(
    version: json['v'] as int? ?? 1,
    revision: json['revision'] as int? ?? 0,
    entries: ((json['entries'] as List?) ?? const [])
        .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
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

### Task 5: VaultStorage —— 原子文件读写

**Files:**
- Create: `lib/services/vault/vault_storage.dart`
- Test: `test/services/vault/vault_storage_test.dart`

**Interfaces:**
- Consumes: `VaultCrypto`（Task 2）、`VaultEntry`/`VaultBody`/`VaultAttachment`（Task 3）、`VaultContainerCodec`（Task 4）
- Produces:
  - `class VaultStorage { VaultStorage({required Directory dir}); }`
  - `bool get isUnlocked` / `int get revision`
  - `Future<bool> exists()`
  - `List<VaultEntry> get entries`
  - `Future<String> createVault(String passphrase)` — 返回恢复码
  - `Future<bool> unlock(String passphrase)`
  - `void lock()`
  - `Future<void> saveEntry(VaultEntry entry)` / `Future<void> deleteEntry(String id)`
  - `Uint8List? attachmentBytes(String id)` / `String? attachmentMimeType(String id)`
  - `Future<void> addAttachment(VaultAttachment a)` / `Future<void> removeAttachment(String id)`
  - `Future<Uint8List?> readEncryptedIndexBytes()` / `Future<Uint8List?> readEncryptedAttachmentBytes()`
  - `Future<bool> adoptRemoteIndex(Uint8List idxBytes, String passphrase)` — 换机恢复：内存验证通过才落盘
  - `Future<bool> adoptRemoteAttachments(Uint8List atcBytes)` — 已解锁状态下同上

这个类是**可实例化的普通类**而非静态 service（见 Global Constraints），构造时注入 `Directory`，测试用临时目录，生产环境由 Task 6 的 `VaultController` 传入 `Application Support/blob/`。

**文件格式（无任何明文头字节）**：

```
idx.bin: [0..76) 口令 keyslot | [76..152) 恢复码 keyslot | [152..) AES-GCM(MK, body JSON)
atc.bin: [0..) AES-GCM(MK, TLV 容器)
```

- [ ] **Step 1: 写失败测试**

```dart
// test/services/vault/vault_storage_test.dart
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

  test('idx.bin 损坏时回退读 .bak 仍能解锁', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');
    await storage.saveEntry(_entry('e1', '第一版'));
    await storage.saveEntry(_entry('e2', '第二版')); // 触发 .bak 生成
    storage.lock();

    // 把主文件写坏
    await File('${tempDir.path}/idx.bin').writeAsBytes(
      Uint8List.fromList(List.filled(200, 0)),
    );

    final ok = await storage.unlock('CorrectHorse1');

    expect(ok, isTrue, reason: '主文件损坏应回退到 .bak');
  });

  test('截断的文件不抛异常，只返回 false', () async {
    final storage = VaultStorage(dir: tempDir);
    await storage.createVault('CorrectHorse1');
    storage.lock();
    await File('${tempDir.path}/idx.bin').writeAsBytes(
      Uint8List.fromList([1, 2, 3]),
    );
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
    expect(local.entries.single.content, '本地珍贵数据',
        reason: '验证失败必须在覆盖之前拦住');

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

    await storage.addAttachment(VaultAttachment(
      id: 'a1',
      mimeType: 'image/jpeg',
      bytes: Uint8List.fromList([9, 8, 7]),
    ));

    expect(storage.attachmentBytes('a1'), Uint8List.fromList([9, 8, 7]));
    expect(storage.attachmentMimeType('a1'), 'image/jpeg');

    await storage.removeAttachment('a1');
    expect(storage.attachmentBytes('a1'), isNull);
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

/// 隐私空间的文件级读写。
///
/// idx.bin（文字，小，频繁重写）+ atc.bin（附件，大，仅增删附件时重写），共用同一把 MK。
///
/// 文件头没有任何明文字节：两个固定 keyslot 之后直接是密文。
/// 版本号/revision 放在加密后的 body 里（[VaultBody]）。
///
/// 所有写盘走 [_atomicWrite]（tmp → rename 备份 → rename 就位），
/// 读取时主文件解不开就回退 .bak——AEAD 的特性是坏一个字节整个文件报废，
/// 日记数据不能因为一次崩溃全丢。
class VaultStorage {
  VaultStorage({required this.dir});

  final Directory dir;

  static const _keyslotLength = 76;
  static const _headerLength = _keyslotLength * 2; // 152
  static const _minBodyLength = 12 + 16; // nonce + mac

  File get _idxFile => File(p.join(dir.path, 'idx.bin'));
  File get _idxBak => File(p.join(dir.path, 'idx.bin.bak'));
  File get _atcFile => File(p.join(dir.path, 'atc.bin'));
  File get _atcBak => File(p.join(dir.path, 'atc.bin.bak'));

  SecretKey? _masterKey;
  Uint8List? _passwordSlot;
  Uint8List? _recoverySlot;
  List<VaultEntry> _entries = [];
  List<VaultAttachment> _attachments = [];
  int _revision = 0;

  bool get isUnlocked => _masterKey != null;
  int get revision => _revision;
  List<VaultEntry> get entries => List.unmodifiable(_entries);

  Future<bool> exists() async =>
      await _idxFile.exists() || await _idxBak.exists();

  SecretKey _requireKey() {
    final mk = _masterKey;
    if (mk == null) throw StateError('隐私空间已锁定，拒绝写入');
    return mk;
  }

  // ── 创建 / 解锁 / 锁定 ────────────────────────────────────────

  Future<String> createVault(String passphrase) async {
    final mk = await VaultCrypto.generateMasterKey();
    final recoveryCode = VaultCrypto.generateRecoveryCode();

    _masterKey = mk;
    _passwordSlot = await VaultCrypto.wrapMasterKey(mk, passphrase);
    _recoverySlot = await VaultCrypto.wrapMasterKey(mk, recoveryCode);
    _entries = [];
    _attachments = [];
    _revision = 0;

    if (!await dir.exists()) await dir.create(recursive: true);
    await _flushIndex();
    await _flushAttachments();

    return recoveryCode;
  }

  /// 解锁。任何失败（口令错、文件截断、格式损坏、JSON 非法）一律返回 false，
  /// 绝不让异常冒泡——崩溃本身就会暴露"刚才那次输入走了特殊代码路径"。
  Future<bool> unlock(String passphrase) async {
    for (final file in [_idxFile, _idxBak]) {
      if (!await file.exists()) continue;
      final loaded = await _tryLoadIndexFrom(await file.readAsBytes(), passphrase);
      if (loaded == null) continue;
      _applyLoaded(loaded);
      await _loadAttachments();
      return true;
    }
    return false;
  }

  void lock() {
    _masterKey = null;
    _passwordSlot = null;
    _recoverySlot = null;
    _entries = [];
    _attachments = [];
    _revision = 0;
  }

  // ── 解析（纯内存，不碰磁盘） ──────────────────────────────────

  Future<_LoadedIndex?> _tryLoadIndexFrom(
    Uint8List raw,
    String credential,
  ) async {
    try {
      if (raw.length < _headerLength + _minBodyLength) return null;
      final pwSlot = raw.sublist(0, _keyslotLength);
      final recSlot = raw.sublist(_keyslotLength, _headerLength);

      var mk = await VaultCrypto.tryUnwrapMasterKey(pwSlot, credential);
      mk ??= await VaultCrypto.tryUnwrapMasterKey(recSlot, credential);
      if (mk == null) return null;

      final plain = await VaultCrypto.decryptBlob(mk, raw.sublist(_headerLength));
      if (plain == null) return null;

      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map<String, dynamic>) return null;
      final body = VaultBody.fromJson(decoded);

      return _LoadedIndex(mk: mk, passwordSlot: pwSlot, recoverySlot: recSlot, body: body);
    } catch (_) {
      return null; // 格式损坏一律当"打不开"，不区分原因
    }
  }

  void _applyLoaded(_LoadedIndex loaded) {
    _masterKey = loaded.mk;
    _passwordSlot = loaded.passwordSlot;
    _recoverySlot = loaded.recoverySlot;
    _entries = loaded.body.entries;
    _revision = loaded.body.revision;
  }

  Future<void> _loadAttachments() async {
    final mk = _masterKey;
    if (mk == null) return;
    for (final file in [_atcFile, _atcBak]) {
      if (!await file.exists()) continue;
      try {
        final plain = await VaultCrypto.decryptBlob(mk, await file.readAsBytes());
        if (plain == null) continue;
        _attachments = VaultContainerCodec.decodeAttachments(plain);
        return;
      } catch (_) {
        continue;
      }
    }
    _attachments = [];
  }

  // ── 换机恢复：先验证，后落盘 ──────────────────────────────────

  /// 用远端拉回的 idx.bin 恢复本地 vault（新设备场景）。
  ///
  /// 必须先在内存里完整验证（解 keyslot + 解 body + 解析 JSON）才写盘。
  /// 先写盘后验证会在远端损坏或口令不匹配时冲掉本地完好数据。
  Future<bool> adoptRemoteIndex(Uint8List idxBytes, String passphrase) async {
    final loaded = await _tryLoadIndexFrom(idxBytes, passphrase);
    if (loaded == null) return false;

    if (!await dir.exists()) await dir.create(recursive: true);
    await _atomicWrite(_idxFile, idxBytes);
    _applyLoaded(loaded);
    _attachments = [];
    return true;
  }

  /// 用远端拉回的 atc.bin 替换本地附件包（须已解锁）。同样先验证后落盘。
  Future<bool> adoptRemoteAttachments(Uint8List atcBytes) async {
    final mk = _masterKey;
    if (mk == null) return false;
    try {
      final plain = await VaultCrypto.decryptBlob(mk, atcBytes);
      if (plain == null) return false;
      final decoded = VaultContainerCodec.decodeAttachments(plain);
      await _atomicWrite(_atcFile, atcBytes);
      _attachments = decoded;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── 条目读写 ──────────────────────────────────────────────────

  Future<void> saveEntry(VaultEntry entry) async {
    _requireKey();
    _entries = [..._entries.where((e) => e.id != entry.id), entry];
    await _flushIndex();
  }

  Future<void> deleteEntry(String id) async {
    _requireKey();
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

  String? attachmentMimeType(String id) =>
      _attachments.where((a) => a.id == id).firstOrNull?.mimeType;

  Future<void> addAttachment(VaultAttachment attachment) async {
    _requireKey();
    _attachments = [
      ..._attachments.where((a) => a.id != attachment.id),
      attachment,
    ];
    await _flushAttachments();
  }

  Future<void> removeAttachment(String id) async {
    _requireKey();
    _attachments = _attachments.where((a) => a.id != id).toList();
    await _flushAttachments();
  }

  Future<Uint8List?> readEncryptedIndexBytes() async =>
      await _idxFile.exists() ? await _idxFile.readAsBytes() : null;

  Future<Uint8List?> readEncryptedAttachmentBytes() async =>
      await _atcFile.exists() ? await _atcFile.readAsBytes() : null;

  // ── 落盘 ──────────────────────────────────────────────────────

  Future<void> _flushIndex() async {
    final mk = _requireKey();
    _revision++;
    final body = VaultBody(version: 1, revision: _revision, entries: _entries);
    final encrypted = await VaultCrypto.encryptBlob(
      mk,
      Uint8List.fromList(utf8.encode(jsonEncode(body.toJson()))),
    );
    await _atomicWrite(_idxFile, [
      ..._passwordSlot!,
      ..._recoverySlot!,
      ...encrypted,
    ]);
  }

  Future<void> _flushAttachments() async {
    final mk = _requireKey();
    final encrypted = await VaultCrypto.encryptBlob(
      mk,
      VaultContainerCodec.encodeAttachments(_attachments),
    );
    await _atomicWrite(_atcFile, encrypted);
  }

  /// 原子写：tmp → 备份现有 → rename 就位。
  ///
  /// 两次 rename 都是同文件系统内的原子操作。中间窗口里 .bak 持有完好数据，
  /// 所以读取端的规则是"主文件解不开就读 .bak"。
  Future<void> _atomicWrite(File target, List<int> bytes) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);

    final bak = File('${target.path}.bak');
    if (await target.exists()) {
      if (await bak.exists()) await bak.delete();
      await target.rename(bak.path);
    }
    await tmp.rename(target.path);
  }
}

class _LoadedIndex {
  final SecretKey mk;
  final Uint8List passwordSlot;
  final Uint8List recoverySlot;
  final VaultBody body;

  _LoadedIndex({
    required this.mk,
    required this.passwordSlot,
    required this.recoverySlot,
    required this.body,
  });
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/services/vault/vault_storage_test.dart`
Expected: PASS（11 个测试全绿）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/vault/vault_storage.dart test/services/vault/vault_storage_test.dart
git commit -m "feat: 新增 VaultStorage，原子写入 + 损坏回退 + 换机恢复"
```

---

### Task 6: VaultController —— 会话状态与锁定广播

**Files:**
- Create: `lib/services/vault/vault_controller.dart`
- Modify: `lib/main.dart`
- Test: `test/services/vault/vault_controller_test.dart`

**Interfaces:**
- Consumes: `VaultStorage`（Task 5）
- Produces:
  - `class VaultController with WidgetsBindingObserver`
  - `static Future<void> VaultController.init()` / `static VaultController get instance`
  - `ValueListenable<bool> get isUnlockedListenable` — **UI 必须监听它做锁定后自动退出**
  - `bool get isUnlocked` / `int get revision`
  - `Future<bool> vaultExists()`
  - `Future<String> createVault(String passphrase)`
  - `Future<bool> tryUnlock(String candidate)`
  - `void lock()`
  - `List<VaultEntry> get entries`
  - `Future<void> saveEntry(VaultEntry entry)` / `Future<void> deleteEntry(String id)`
  - `Future<void> addAttachment(VaultAttachment a)` / `Uint8List? attachmentBytes(String id)` / `String? attachmentMimeType(String id)`
  - `VaultStorage get storage` — 供 Task 12/13 的迁移与同步使用
  - `void attachLifecycleObserver()`
  - `@visibleForTesting VaultController.forTesting(VaultStorage storage)`

- [ ] **Step 1: 写失败测试**

只测纯状态逻辑；真实 `AppLifecycleState` 回调链路在 Task 8/9 手动验证。

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
```

> 测试文件顶部还需 `import 'package:isle_log/data/models/vault_entry.dart';`。

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/services/vault/vault_controller_test.dart`
Expected: FAIL，找不到 `lib/services/vault/vault_controller.dart`。

- [ ] **Step 3: 实现**

```dart
// lib/services/vault/vault_controller.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database/database_service.dart';
import '../../data/models/vault_entry.dart';
import 'vault_storage.dart';

/// 隐私空间会话状态：解锁/锁定、后台超时自动锁定。
///
/// [isUnlockedListenable] 是锁定事件的唯一广播渠道——UI 必须监听它，
/// 在收到 false 时清空输入并退出页面。否则会出现"计时器已锁定、
/// 编辑器还开着并持有明文、此时点保存直接崩溃"。
class VaultController with WidgetsBindingObserver {
  VaultController._(this._storage);

  @visibleForTesting
  VaultController.forTesting(VaultStorage storage) : _storage = storage;

  static VaultController? _instance;

  static VaultController get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('VaultController 尚未初始化，请先 await VaultController.init()');
    }
    return i;
  }

  static Future<void> init() async {
    if (_instance != null) return;
    final supportDir = await getApplicationSupportDirectory();
    // 中性目录名；不用系统 Caches（会被系统清空，日记数据不可接受）
    final dir = Directory(p.join(supportDir.path, 'blob'));
    _instance = VaultController._(VaultStorage(dir: dir));
  }

  final VaultStorage _storage;
  final ValueNotifier<bool> _isUnlocked = ValueNotifier(false);
  DateTime? _backgroundedAt;

  static const _backgroundLockTimeout = Duration(seconds: 60);

  ValueListenable<bool> get isUnlockedListenable => _isUnlocked;
  bool get isUnlocked => _storage.isUnlocked;
  int get revision => _storage.revision;
  List<VaultEntry> get entries => _storage.entries;
  VaultStorage get storage => _storage;

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
    if (!_storage.isUnlocked) return;
    _storage.lock();
    _isUnlocked.value = false;
  }

  Future<void> saveEntry(VaultEntry entry) async {
    entry.tags = DatabaseService.extractTags(entry.content);
    entry.updatedAt = DateTime.now();
    await _storage.saveEntry(entry);
  }

  Future<void> deleteEntry(String id) => _storage.deleteEntry(id);

  Future<void> addAttachment(VaultAttachment attachment) =>
      _storage.addAttachment(attachment);

  Uint8List? attachmentBytes(String id) => _storage.attachmentBytes(id);
  String? attachmentMimeType(String id) => _storage.attachmentMimeType(id);

  void attachLifecycleObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// 只处理 paused。
  ///
  /// 不纳入 inactive / hidden：下拉通知栏、来电横幅、权限弹窗都会触发那两个状态，
  /// 把它们算进锁定计时会让正常操作频繁掉锁，而且对任务切换器截图问题毫无帮助
  /// ——那个由 Task 15 的截屏防护解决。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isUnlocked) return;
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null &&
          DateTime.now().difference(since) > _backgroundLockTimeout) {
        lock();
      }
    }
  }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/services/vault/vault_controller_test.dart`
Expected: PASS（5 个测试全绿）。

- [ ] **Step 5: 接入 main.dart**

在 `lib/main.dart` 的 `WidgetsFlutterBinding.ensureInitialized();` 之后加（Task 14 会给它包上 `kVaultEnabled` 判断）：

```dart
  await VaultController.init();
  VaultController.instance.attachLifecycleObserver();
```

文件顶部加 `import 'services/vault/vault_controller.dart';`。

- [ ] **Step 6: Commit**

```bash
git add lib/services/vault/vault_controller.dart test/services/vault/vault_controller_test.dart lib/main.dart
git commit -m "feat: 新增 VaultController，会话状态与锁定广播"
```

---

### Task 7: 搜索框口令钩子（仅回车触发）

**Files:**
- Create: `lib/features/vault/vault_entry_gate.dart`
- Modify: `lib/features/home/home_view.dart`
- Test: `test/features/vault/vault_entry_gate_test.dart`

**Interfaces:**
- Consumes: `VaultController.instance`（Task 6）
- Produces:
  - `enum VaultInputKind { none, create, unlock, recover }`
  - `static VaultInputKind VaultEntryGate.classify(String raw, {required bool vaultExists, required bool serverConfigured})` — 纯函数，可单测
  - `static Future<bool> VaultEntryGate.handle(BuildContext context, String raw)` — 返回 true 表示已接管（已跳转），调用方不再展示搜索结果

**关键设计：只在回车提交路径触发**

Flutter SDK 的 `search.dart` 里，逐键输入走 `buildSuggestions`，回车（`onSubmitted → showResults`，第 648 行）才走 `buildResults`。判定只能挂在后者。

挂在逐键路径上的后果：用户每输入一个 ≥8 字符的普通搜索词都会跑一次 32MB Argon2id，口令槽不中还要再跑一次恢复码槽——既是明显卡顿，也是时间侧信道（"输入某些词时 App 会卡一下"本身就可观察）。

再加一层内存缓存：同一个已失败的候选串重复提交时直接返回，不重复跑 KDF。

**三种前缀**

| 输入 | 前置条件 | 行为 |
|---|---|---|
| `+口令` | 本地无 vault，口令含大小写+数字、长度≥8、无空格 | 创建 |
| `口令` | 本地有 vault，长度≥8、无空格 | 解锁 |
| `?口令` | 本地无 vault，已配置服务端，长度≥8、无空格 | 换机恢复（Task 13） |

任何条件不满足一律走普通搜索，不给任何反馈。

- [ ] **Step 1: 写 classify 的失败测试**

```dart
// test/features/vault/vault_entry_gate_test.dart
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
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/features/vault/vault_entry_gate_test.dart`
Expected: FAIL，找不到 `lib/features/vault/vault_entry_gate.dart`。

- [ ] **Step 3: 实现**

```dart
// lib/features/vault/vault_entry_gate.dart
import 'package:flutter/material.dart';

import '../../services/settings/settings_service.dart';
import '../../services/vault/vault_controller.dart';
import '../../services/vault/vault_sync.dart';
import 'vault_page.dart';

enum VaultInputKind { none, create, unlock, recover }

/// 搜索框输入的口令识别与分派。
///
/// 单独成文件（而不是塞进已有 1400 行的 home_view.dart）：分类逻辑是纯函数，
/// 拿出来才能单测；home_view 那边只留一行调用。
class VaultEntryGate {
  VaultEntryGate._();

  /// 上一个已尝试且失败的候选串。同一个词重复提交时直接跳过，不重复跑 Argon2id。
  static String? _lastFailedCandidate;

  /// 纯函数分类。不碰磁盘、不碰网络，供单测直接调用。
  static VaultInputKind classify(
    String raw, {
    required bool vaultExists,
    required bool serverConfigured,
  }) {
    if (raw.startsWith('+')) {
      final passphrase = raw.substring(1);
      if (vaultExists) return VaultInputKind.none;
      return _isStrong(passphrase) ? VaultInputKind.create : VaultInputKind.none;
    }
    if (raw.startsWith('?')) {
      final passphrase = raw.substring(1);
      if (vaultExists || !serverConfigured) return VaultInputKind.none;
      return _isPlausible(passphrase)
          ? VaultInputKind.recover
          : VaultInputKind.none;
    }
    if (!vaultExists) return VaultInputKind.none;
    return _isPlausible(raw) ? VaultInputKind.unlock : VaultInputKind.none;
  }

  /// 解锁/恢复的门槛：够长、无空格。不要求字符类组合——
  /// 失败的代价只是一次静默的空搜索结果。
  static bool _isPlausible(String s) => s.length >= 8 && !s.contains(' ');

  /// 创建的门槛：额外要求大小写字母 + 数字。
  ///
  /// 防止日常搜索里凑巧输入一个 8 位以上、以 '+' 开头的词（如 "+项目截止0824"）
  /// 被误判成创建请求；顺带保证真口令有基本强度。
  static bool _isStrong(String s) =>
      _isPlausible(s) &&
      s.contains(RegExp(r'[a-z]')) &&
      s.contains(RegExp(r'[A-Z]')) &&
      s.contains(RegExp(r'[0-9]'));

  /// 返回 true 表示已接管（已跳转到隐私空间），调用方不应再展示搜索结果。
  ///
  /// ⚠️ 只能从 SearchDelegate.buildResults 路径调用，绝不能从 buildSuggestions
  /// 调用——那会让每次按键都跑一次 32MB Argon2id。
  static Future<bool> handle(BuildContext context, String raw) async {
    if (raw == _lastFailedCandidate) return false;

    final vaultExists = await VaultController.instance.vaultExists();
    final serverConfigured = await SettingsService.isConfigured;
    final kind = classify(
      raw,
      vaultExists: vaultExists,
      serverConfigured: serverConfigured,
    );
    if (kind == VaultInputKind.none) return false;

    switch (kind) {
      case VaultInputKind.create:
        return _handleCreate(context, raw.substring(1));
      case VaultInputKind.unlock:
        final ok = await VaultController.instance.tryUnlock(raw);
        if (!ok) {
          _lastFailedCandidate = raw;
          return false;
        }
        _lastFailedCandidate = null;
        if (!context.mounted) return true;
        _enterVault(context);
        return true;
      case VaultInputKind.recover:
        final ok = await VaultSync.recoverFromRemote(raw.substring(1));
        if (!ok) {
          _lastFailedCandidate = raw;
          return false;
        }
        _lastFailedCandidate = null;
        if (!context.mounted) return true;
        _enterVault(context);
        return true;
      case VaultInputKind.none:
        return false;
    }
  }

  static Future<bool> _handleCreate(
    BuildContext context,
    String passphrase,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建隐私空间？'),
        content: Text('口令：$passphrase\n\n忘记口令将无法恢复数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认创建'),
          ),
        ],
      ),
    );
    if (confirmed != true) return true; // 用户取消：已接管，但不展示搜索结果

    final code = await VaultController.instance.createVault(passphrase);
    if (!context.mounted) return true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复码'),
        content: Text(
          '忘记口令时可用此码解锁：\n\n$code\n\n'
          '请抄下并妥善保管，此码只显示这一次。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我已记录'),
          ),
        ],
      ),
    );
    if (!context.mounted) return true;
    _enterVault(context);
    return true;
  }

  static void _enterVault(BuildContext context) {
    Navigator.of(context).pop(); // 关闭搜索页
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VaultPage()),
    );
  }
}
```

> `VaultSync.recoverFromRemote` 由 Task 13 实现。本任务先写好调用点——Task 7 与 Task 13 之间存在这一处前向依赖，中间的任务不影响编译（`vault_sync.dart` 在 Task 13 创建），因此执行顺序上 Task 7 完成后到 Task 13 完成前，`vault_entry_gate.dart` 无法编译通过。执行者可先在 Task 7 里创建一个只含 `recoverFromRemote` 桩（`return false;`）的 `vault_sync.dart`，Task 13 再填充完整实现。

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/features/vault/vault_entry_gate_test.dart`
Expected: PASS（14 个测试全绿）。

- [ ] **Step 5: 接进 home_view.dart —— 只走 buildResults**

给 `_SearchResults` 加一个 `submitted` 标志，用来区分逐键输入和回车提交。

修改 `_MemoSearchDelegate`（约第 1145 行）：

```dart
  @override
  Widget buildResults(BuildContext context) =>
      _SearchResults(query: query, submitted: true);

  @override
  Widget buildSuggestions(BuildContext context) => query.isEmpty
      ? const SizedBox()
      : _SearchResults(query: query, submitted: false);
```

修改 `_SearchResults`（约第 1166 行）：

```dart
class _SearchResults extends StatefulWidget {
  final String query;
  final bool submitted;
  const _SearchResults({required this.query, required this.submitted});
  // ...
}
```

修改 `_SearchResultsState._doSearch`（约第 1198 行），在原有逻辑最前面插入：

```dart
  Future<void> _doSearch(String q) async {
    if (q == _lastQuery) return;
    _lastQuery = q;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    // 只在回车提交时判定口令——逐键输入路径绝不触发，否则每按一个键
    // 都可能跑一次 32MB Argon2id（卡顿 + 时间侧信道）。
    if (widget.submitted && mounted) {
      final handled = await VaultEntryGate.handle(context, q);
      if (handled) return;
    }

    setState(() => _loading = true);
    // ...（原有逻辑不变）
```

文件顶部加 import：

```dart
import '../vault/vault_entry_gate.dart';
```

（Task 14 会给这个调用包上 `kVaultEnabled` 判断。）

- [ ] **Step 6: 手动验证**

1. `flutter run`
2. 搜索框输入 `+testpass123`（全小写+数字，强度不够）回车 → 表现为普通搜索，**不**弹创建框
3. 输入 `+Testpass123` 回车 → 弹出创建确认框
4. 确认后看到恢复码弹窗，关闭后进入隐私空间页
5. 返回主页，输入 `Testpass123` 回车 → 直接进入隐私空间页
6. **关键**：输入一个 12 位以上的普通词（如 `internationalization`），观察逐个字符输入过程**不卡顿**；回车后才会有一次短暂延迟，随后正常显示"没有找到"

- [ ] **Step 7: Commit**

```bash
git add lib/features/vault/vault_entry_gate.dart test/features/vault/vault_entry_gate_test.dart lib/features/home/home_view.dart
git commit -m "feat: 搜索框口令钩子，仅回车触发，含创建/解锁/恢复三种前缀"
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
    // 后台超时锁定时必须把页面主动弹掉——否则会停在一个已经没有密钥、
    // 却仍在展示已解密内容的页面上。
    VaultController.instance.isUnlockedListenable.addListener(_onLockChanged);
  }

  void _onLockChanged() {
    if (!VaultController.instance.isUnlocked && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _loadMain() async {
    final memos = await DatabaseService.getAllMemos();
    if (mounted) setState(() => _mainMemos = memos);
  }

  @override
  void dispose() {
    VaultController.instance.isUnlockedListenable.removeListener(_onLockChanged);
    VaultController.instance.lock(); // 离开页面即锁定
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
    VaultController.instance.isUnlockedListenable.addListener(_onLockChanged);
  }

  /// 后台超时锁定时，清空输入框并退出。
  ///
  /// 不做这件事的后果：编辑器仍持有明文，且此时点保存会走到已经没有主密钥的
  /// 存储层（Task 5 的 `_requireKey()` 会抛 StateError）。
  void _onLockChanged() {
    if (!VaultController.instance.isUnlocked && mounted) {
      _controller.clear();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    VaultController.instance.isUnlockedListenable.removeListener(_onLockChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!VaultController.instance.isUnlocked) {
      // 保存过程中刚好被后台超时锁掉：直接退出，不尝试写入。
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
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
6. **锁定退出验证**：把 `VaultController._backgroundLockTimeout` 临时改成 3 秒 → 打开编辑器输入一些文字 → 切到后台等 5 秒 → 切回 → 应自动弹回主页，且不崩溃；此时再进隐私空间需重新输口令。验证完把超时改回 60 秒

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
    final imageIds = entry.attachmentIds
        .where((id) =>
            VaultController.instance.attachmentMimeType(id)?.startsWith('image/') ??
            false)
        .toList();
    if (imageIds.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: imageIds.map((id) {
          final bytes = VaultController.instance.attachmentBytes(id);
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

> `attachmentMimeType` 已在 Task 5/6 的接口里定义好，直接用即可。非图片（音频）附件在卡片里显示一个可点击的播放图标，点击后用 `AudioPlayer().setAudioSource(VaultByteAudioSource(bytes, mimeType: mime))` 播放——写法与上面的缩略图分支对称，仅 widget 不同，不重复列出。

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

### Task 11: API 补齐 —— 硬删除 + 按 memo 列附件 + 下载字节

**Files:**
- Modify: `lib/services/api/memos_api_service.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `Future<void> MemosApiService.deleteMemo(String name, {bool hard = false})`
  - `Future<List<Map<String, dynamic>>> MemosApiService.listMemoAttachments(String memoId)`
  - `Future<Uint8List?> MemosApiService.downloadAttachmentBytes(String resName, String filename)`

后两个是 Task 13 换机恢复要用的：拉回 `backup.dat`（即 `atc.bin` 密文）需要先列出封面 memo 的附件，再按资源名下载字节。现有 `AttachmentService.downloadToLocal` 会把文件写到本地磁盘，vault 场景不能用——附件密文必须直接进内存。

对应文档：`server-API.md` 的「列出 Memo 的附件」`GET /api/v1/memos/:id/attachments`（响应 `{"attachments":[...]}`）和「下载附件」`GET /file/attachments/:id/:filename`。

**⚠️ 阻塞说明**：`?hard=true` 需要服务端新增对应处理逻辑（物理删除 memo 行 + 其版本历史表记录），服务端代码不在本仓库，需要在 islelog-server 项目里单独实现和部署。在服务端就绪前，Task 12 的移入功能调用这个接口时，效果等同于当前的软删除——明文仍留在服务端数据库，这是已知的、暂时无法在客户端侧解决的缺口（已在 spec 第 11 节标注）。另两个接口服务端已存在，不阻塞。

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

- [ ] **Step 3: 新增按 memo 列附件 + 下载字节到内存**

在同一文件里，`deleteAttachment`（约第 365 行）之后追加：

```dart
  /// 列出某条 memo 关联的附件
  ///
  /// [memoId]：纯数字 id（不含 "memos/" 前缀）
  Future<List<Map<String, dynamic>>> listMemoAttachments(String memoId) async {
    debugPrint('[API] listMemoAttachments memoId=$memoId');
    try {
      final res = await _dio.get('/api/v1/memos/$memoId/attachments');
      final list = (res.data['attachments'] as List?) ?? const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 直接把附件下载成内存字节，不落地。
  ///
  /// 与 [AttachmentService.downloadToLocal] 的区别：那个会写本地文件，
  /// 隐私空间的附件密文不能经过磁盘中转。失败返回 null，不抛异常。
  ///
  /// [resName]：形如 "attachments/456"
  Future<Uint8List?> downloadAttachmentBytes(
    String resName,
    String filename,
  ) async {
    final path = '/file/$resName/${Uri.encodeComponent(filename)}';
    debugPrint('[API] downloadAttachmentBytes $path');
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException catch (e) {
      debugPrint('[API] downloadAttachmentBytes 失败：$e');
      return null;
    }
  }
```

文件顶部确认已 `import 'dart:typed_data';`（若无则补上）。

- [ ] **Step 4: 确认无编译错误**

Run: `flutter analyze lib/services/api/memos_api_service.dart`
Expected: 无 error（原调用点 `deleteMemo(name)` 因为 `hard` 有默认值，不需要改动）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/api/memos_api_service.dart
git commit -m "feat: API 补齐硬删除参数、按 memo 列附件、下载附件字节"
```

---

### Task 12: 移入 / 移出（含级联清理）

**Files:**
- Create: `lib/services/vault/vault_migration.dart`
- Modify: `lib/features/vault/vault_page.dart`

**Interfaces:**
- Consumes: `DatabaseService`（现有）、`AttachmentService`（现有）、`MemosApiService`（Task 11）、`VaultController`（Task 6）
- Produces:
  - `enum VaultMigrationResult { ok, blockedPendingSync, failed }`
  - `Future<VaultMigrationResult> VaultMigration.moveIntoVault(MemoEntry memo)`
  - `Future<VaultMigrationResult> VaultMigration.moveOutOfVault(VaultEntry entry)`

**移入必须做的四类清理**——只删 `MemoEntry` 会留下四处残留，逐条对应现有代码：

| 残留 | 为什么 | 用什么清 |
|---|---|---|
| 本地附件明文文件 | `attachmentsJson` 里的 `localPath` 指向应用附件目录里的明文文件，包括刚 `downloadToLocal` 拉回的那份副本 | `AttachmentService.deleteLocal(localPath)` |
| 评论 | `CommentEntry.memoId` 仍指向已删 memo，`searchComments` 仍能搜到其明文内容 | `getCommentsByMemoId(id)` → 逐个 `hardDeleteComment` |
| 事件串成员引用 | `ThreadEntry.memberLocalIds` 仍含该 memo id。现有 `softDelete`（`database_service.dart:166`）调了清理，`hardDelete`（:172）**没调**——这是既存缺口 | `removeMemoFromAllThreads(id)`（`database_service.dart:1451`） |
| 同步竞态 | 后台 `pushPendingBackground()` 可能正在推这条 memo，导致"远端删完又被重建" | 前置检查 `syncStatus == pending` 时拒绝，不引入"暂停同步引擎"这种重机制 |

**移出必须还原附件**，不能静默销毁——`deleteEntry` 会连带把 `atc.bin` 里的附件字节删掉（Task 5 的实现），照片/录音就永久没了。做法是解密字节 → 临时文件 → `AttachmentService.saveLocally()` → 挂到新 `MemoEntry` → 删临时文件。不采用"弹窗告知附件将被删除"的替代方案：数据不该丢。

- [ ] **Step 1: 实现**

无预写单测——依赖真实网络 IO 和 Isar，与 `sync_service.dart` 里同类集成函数的现状一致（那些函数也没有直接单测，只有其内部纯逻辑被抽成 `*_policy.dart` 单测）。验证靠 Step 3 的手动流程。

```dart
// lib/services/vault/vault_migration.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../data/database/database_service.dart';
import '../../data/models/attachment_info.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/vault_entry.dart';
import '../api/memos_api_service.dart';
import '../attachment/attachment_service.dart';
import '../settings/settings_service.dart';
import 'vault_controller.dart';

enum VaultMigrationResult { ok, blockedPendingSync, failed }

/// 普通日记 ⇄ 隐私空间之间的移入/移出。
class VaultMigration {
  VaultMigration._();

  /// 普通日记 → vault。
  ///
  /// 前置拒绝 pending：移入过程要删远端条目，而后台 pushPendingBackground()
  /// 可能正在推送这条 memo，会导致"远端删完又被重建"。用前置条件关掉这个
  /// 竞态窗口，比引入暂停同步引擎的机制简单可靠。
  static Future<VaultMigrationResult> moveIntoVault(MemoEntry memo) async {
    if (memo.syncStatus == SyncStatus.pending) {
      return VaultMigrationResult.blockedPendingSync;
    }
    if (!VaultController.instance.isUnlocked) {
      return VaultMigrationResult.failed;
    }

    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    final api = (url != null && url.isNotEmpty && token != null && token.isNotEmpty)
        ? MemosApiService(baseUrl: url, token: token)
        : null;

    // ── 1. 收集附件字节，写进 vault ──
    final attachmentIds = <String>[];
    final resolved = <AttachmentInfo>[];
    for (final att in memo.attachments) {
      var local = att;
      final missing =
          local.localPath == null || !File(local.localPath!).existsSync();
      if (missing && url != null && token != null) {
        local = await AttachmentService.downloadToLocal(att, url, token);
      }
      if (local.localPath == null) {
        debugPrint('[VaultMigration] 附件无法取得字节，跳过：${local.filename}');
        continue;
      }
      final bytes = await File(local.localPath!).readAsBytes();
      final id = const Uuid().v4();
      await VaultController.instance.addAttachment(
        VaultAttachment(id: id, mimeType: local.mimeType, bytes: bytes),
      );
      attachmentIds.add(id);
      resolved.add(local);
    }

    final entry = VaultEntry(
      id: const Uuid().v4(),
      content: memo.content,
      createdAt: memo.createdAt,
      updatedAt: DateTime.now(),
      tags: const [],
      attachmentIds: attachmentIds,
      movedFromMemosName: memo.memosName,
    );
    await VaultController.instance.saveEntry(entry);

    // ── 2. 远端硬删除（memo + 附件资源） ──
    if (api != null && memo.memosName != null) {
      try {
        for (final att in memo.attachments) {
          if (att.remoteResName != null) {
            await api.deleteAttachment(att.remoteResName!);
          }
        }
        await api.deleteMemo(memo.memosName!, hard: true);
      } catch (e) {
        debugPrint('[VaultMigration] 远端删除失败：$e');
        return VaultMigrationResult.failed;
      }
    }

    // ── 3. 本地级联清理 ──
    // 3a. 附件明文文件（含刚下载的副本）
    for (final att in resolved) {
      if (att.localPath != null) {
        await AttachmentService.deleteLocal(att.localPath!);
      }
    }
    // 3b. 评论——否则 CommentEntry 仍持明文且能被主库搜索命中
    final comments = await DatabaseService.getCommentsByMemoId(memo.id);
    for (final c in comments) {
      await DatabaseService.hardDeleteComment(c.id);
    }
    // 3c. 事件串成员引用——softDelete 做了这步，hardDelete 没做
    await DatabaseService.removeMemoFromAllThreads(memo.id);
    // 3d. 最后删 memo 本体
    await DatabaseService.hardDelete(memo.id);

    return VaultMigrationResult.ok;
  }

  /// vault → 普通日记。附件字节完整还原，不静默销毁。
  static Future<VaultMigrationResult> moveOutOfVault(VaultEntry entry) async {
    if (!VaultController.instance.isUnlocked) {
      return VaultMigrationResult.failed;
    }

    // ── 1. 附件先还原成正常附件（经临时文件过渡给 AttachmentService） ──
    final restored = <AttachmentInfo>[];
    Directory? tmpDir;
    try {
      for (final attId in entry.attachmentIds) {
        final bytes = VaultController.instance.attachmentBytes(attId);
        final mime = VaultController.instance.attachmentMimeType(attId);
        if (bytes == null) continue;

        tmpDir ??= await Directory.systemTemp.createTemp('vault_out_');
        final ext = _extensionFor(mime ?? 'application/octet-stream');
        final tmpFile = File(p.join(tmpDir.path, '$attId$ext'));
        await tmpFile.writeAsBytes(bytes, flush: true);

        restored.add(
          await AttachmentService.saveLocally(
            tmpFile,
            filename: '$attId$ext',
            compress: false, // 已经是最终字节，不再压一次
          ),
        );
      }
    } catch (e) {
      debugPrint('[VaultMigration] 附件还原失败，中止移出：$e');
      await tmpDir?.delete(recursive: true);
      return VaultMigrationResult.failed;
    } finally {
      // 临时明文文件用完立刻删
      await tmpDir?.delete(recursive: true);
    }

    // ── 2. 建主库条目 ──
    final memo = MemoEntry()
      ..content = entry.content
      ..createdAt = entry.createdAt
      ..updatedAt = DateTime.now()
      ..attachments = restored;
    await DatabaseService.saveMemo(memo);

    // ── 3. 全部成功后才从 vault 移除 ──
    await VaultController.instance.deleteEntry(entry.id);
    return VaultMigrationResult.ok;
  }

  static String _extensionFor(String mime) => switch (mime) {
    'image/jpeg' => '.jpg',
    'image/png' => '.png',
    'image/gif' => '.gif',
    'image/webp' => '.webp',
    'audio/aac' || 'audio/mp4' => '.m4a',
    'audio/mpeg' => '.mp3',
    _ => '.bin',
  };
}
```

- [ ] **Step 2: 在 VaultPage 加入口**

`_MainItem` 分支的 `ListTile` 加 `onLongPress`：

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
                          content: const Text('原日记及其评论将从主时间线永久移除。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('移入'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      final result = await VaultMigration.moveIntoVault(memo);
                      if (!context.mounted) return;
                      switch (result) {
                        case VaultMigrationResult.ok:
                          await _loadMain();
                          setState(() {});
                        case VaultMigrationResult.blockedPendingSync:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('这条日记还有未同步的改动，请先完成同步')),
                          );
                        case VaultMigrationResult.failed:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('移入失败，请稍后重试')),
                          );
                      }
                    },
                  ),
```

`_VaultItem` 分支同理加一个"移出"入口（`VaultEntryCard` 上加 `onLongPress` 回调），调用 `VaultMigration.moveOutOfVault(entry)`，成功后 `_loadMain()` + `setState`——分支处理与上面对称，不重复列出。

文件顶部加 `import '../../services/vault/vault_migration.dart';`。

- [ ] **Step 3: 手动验证**

1. 在隐私空间页长按一条**已同步**的普通日记 → 确认后应从普通分组消失，出现在带锁标记的条目里
2. 返回主页时间线 → 该日记应完全不见；主页搜索它的正文和**它的评论内容** → 都应搜不到
3. 长按一条**有未同步改动**的日记 → 应提示"请先完成同步"，不执行移入
4. 移入一条带图片的日记后，检查应用附件目录（`Application Documents/attachments/`）→ 对应的明文图片文件应已被删除
5. 把刚才那条移出 vault → 图片应重新出现在主库日记里且能正常显示
6. 若已配置服务端：登录后台确认该 memo 已被删除（软删或硬删取决于服务端是否已支持 `?hard=true`，见 Task 11）

- [ ] **Step 4: Commit**

```bash
git add lib/services/vault/vault_migration.dart lib/features/vault/vault_page.dart
git commit -m "feat: 隐私空间移入/移出，含评论/事件串/附件文件级联清理"
```

---

### Task 13: 同步 —— 封面故事 memo + 换机恢复

**Files:**
- Create: `lib/services/vault/vault_sync.dart`（Task 7 若已创建桩文件，此处填充完整实现）
- Modify: `lib/services/sync/sync_service.dart`
- Modify: `lib/services/settings/settings_service.dart`

**Interfaces:**
- Consumes: `VaultController`（Task 6）、`MemosApiService`（Task 11）
- Produces:
  - `Future<void> VaultSync.push()`
  - `Future<void> VaultSync.pullIfNewer()`
  - `Future<bool> VaultSync.recoverFromRemote(String passphrase)` — Task 7 的 `?` 前缀调用
  - `SyncService._applyRemoteMemo` 新增前缀过滤

**同步模型：单设备写 + 换机恢复**

v1 不支持多设备并行编辑。`revision`（Task 3 的 `VaultBody` 字段）提供整体先后取舍：远端 revision 更高就整体采用远端，否则保留本地。两台设备各自离线编辑后先后推送，**后推送的整体覆盖先推送的，没有合并**。

**换机恢复为什么能成立**：MK 是随机生成的、属于 vault 而非设备，keyslot 跟着 `idx.bin` 走（Task 5 的文件格式）。所以新设备只要拿到远端的 `idx.bin`，用同一口令就能解开——**前提是它不能先自己 `createVault`**（那会生成一把无关的新 MK）。这就是为什么恢复要走独立的 `?` 前缀，而不是"解锁失败后自动尝试"。

走显式前缀的另一个原因：避免每次长搜索词失败都触发一次远端全量列表拉取——那既慢又在网络层可观察。

- [ ] **Step 1: SettingsService 加中性命名的资源指针**

在 `lib/services/settings/settings_service.dart` 的 Draft 段附近加：

```dart
  static const _keyEncBackupMemoName = 'enc_backup_memo_name';

  static Future<String?> get encBackupMemoName async =>
      (await _prefs).getString(_keyEncBackupMemoName);

  static Future<void> setEncBackupMemoName(String name) async {
    await (await _prefs).setString(_keyEncBackupMemoName, name);
  }
```

key 名刻意取中性的 `enc_backup_memo_name` 而非 `vault_*`——SharedPreferences 的 key 名在系统备份导出的 XML/plist 里是明文可读的，`vault` 这个词本身就是线索。它存的只是资源指针，不含秘密，与"加密云备份"的封面故事一致。

- [ ] **Step 2: sync_service.dart 加前缀过滤**

在 `_applyRemoteMemo`（约第 913 行）开头插入：

```dart
  static Future<int> _applyRemoteMemo(
    Map<String, dynamic> data,
    String baseUrl, {
    required bool archived,
  }) async {
    final content = data['content'] as String? ?? '';
    if (content.startsWith(VaultSync.contentPrefix)) {
      return 0; // 隐私空间封面故事 memo：不写入主库、不渲染
    }

    final remoteName = data['name'] as String;
    // ...（原有逻辑不变）
```

顶部加 `import '../vault/vault_sync.dart';`。

- [ ] **Step 3: 实现 VaultSync**

```dart
// lib/services/vault/vault_sync.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../api/memos_api_service.dart';
import '../settings/settings_service.dart';
import 'vault_controller.dart';

/// 隐私空间同步：加密后的 idx.bin 作为一条"加密备份" memo 的正文上传，
/// atc.bin 作为该 memo 的附件上传。只在解锁期间进行。
///
/// 对应的前缀过滤见 sync_service.dart 的 _applyRemoteMemo。
class VaultSync {
  VaultSync._();

  static const contentPrefix = 'IsleLog-Backup/1';
  static const _attachmentFilename = 'backup.dat';

  static Future<MemosApiService?> _api() async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return MemosApiService(baseUrl: url, token: token);
  }

  // ── 推送 ──────────────────────────────────────────────────────

  static Future<void> push() async {
    if (!VaultController.instance.isUnlocked) return;
    final api = await _api();
    if (api == null) return;

    final storage = VaultController.instance.storage;
    final idxBytes = await storage.readEncryptedIndexBytes();
    if (idxBytes == null) return;

    final content = '$contentPrefix\n${base64Encode(idxBytes)}';
    final existingName = await SettingsService.encBackupMemoName;

    try {
      String memoName;
      if (existingName != null) {
        await api.updateMemo(
          name: existingName,
          content: content,
          visibility: 'PRIVATE',
        );
        memoName = existingName;
      } else {
        final created = await api.createMemo(
          content: content,
          visibility: 'PRIVATE',
        );
        memoName = created['name'] as String;
        await SettingsService.setEncBackupMemoName(memoName);
      }

      final atcBytes = await storage.readEncryptedAttachmentBytes();
      if (atcBytes != null) await _uploadAttachmentPack(api, memoName, atcBytes);
    } catch (e) {
      debugPrint('[VaultSync] push 失败：$e');
    }
  }

  static Future<void> _uploadAttachmentPack(
    MemosApiService api,
    String memoName,
    Uint8List atcBytes,
  ) async {
    final tmpDir = await Directory.systemTemp.createTemp('vault_sync_');
    try {
      final tmpFile = File(p.join(tmpDir.path, _attachmentFilename));
      await tmpFile.writeAsBytes(atcBytes, flush: true);
      await api.uploadAttachment(
        file: tmpFile,
        filename: _attachmentFilename,
        memoName: memoName,
      );
    } finally {
      await tmpDir.delete(recursive: true);
    }
  }

  // ── 拉取（本机已有 vault，解锁后比对 revision） ──────────────

  static Future<void> pullIfNewer() async {
    if (!VaultController.instance.isUnlocked) return;
    final api = await _api();
    if (api == null) return;
    final existingName = await SettingsService.encBackupMemoName;
    if (existingName == null) return;

    try {
      final remote = await api.getMemo(existingName.split('/').last);
      final idxBytes = _decodeIndexFrom(remote);
      if (idxBytes == null) return;

      // 用当前会话已知可用的凭证去试解远端——解不开说明远端是另一个
      // vault（或损坏），保留本地不动。adoptRemoteIndex 内部先验证后落盘。
      final storage = VaultController.instance.storage;
      final localRevision = storage.revision;
      final probe = await storage.peekRemoteRevision(idxBytes);
      if (probe == null || probe <= localRevision) return;

      await storage.adoptRemoteIndexWithCurrentKey(idxBytes);
      await _pullAttachmentPack(api, remote);
    } catch (e) {
      debugPrint('[VaultSync] pullIfNewer 失败：$e');
    }
  }

  // ── 换机恢复（本机无 vault，用输入的口令解远端） ──────────────

  /// Task 7 的 `?口令` 入口调用。
  ///
  /// 流程：拉远端 memo 列表 → 按前缀找到备份条目 → 内存中用口令试解 keyslot
  /// → 成功才落盘并解锁。任何一步失败都静默返回 false，不落盘、不提示。
  static Future<bool> recoverFromRemote(String passphrase) async {
    if (VaultController.instance.isUnlocked) return false;
    final api = await _api();
    if (api == null) return false;

    try {
      final memos = await api.listAllMemos();
      final backup = memos.where((m) {
        final c = m['content'] as String? ?? '';
        return c.startsWith(contentPrefix);
      }).firstOrNull;
      if (backup == null) return false;

      final idxBytes = _decodeIndexFrom(backup);
      if (idxBytes == null) return false;

      final ok = await VaultController.instance.adoptRemoteIndex(
        idxBytes,
        passphrase,
      );
      if (!ok) return false;

      await SettingsService.setEncBackupMemoName(backup['name'] as String);
      await _pullAttachmentPack(api, backup);
      return true;
    } catch (e) {
      debugPrint('[VaultSync] recoverFromRemote 失败：$e');
      return false;
    }
  }

  // ── 共用 ──────────────────────────────────────────────────────

  static Uint8List? _decodeIndexFrom(Map<String, dynamic> memo) {
    final content = memo['content'] as String? ?? '';
    if (!content.startsWith(contentPrefix)) return null;
    try {
      return base64Decode(content.substring(contentPrefix.length).trim());
    } catch (_) {
      return null;
    }
  }

  static Future<void> _pullAttachmentPack(
    MemosApiService api,
    Map<String, dynamic> memo,
  ) async {
    final memoId = (memo['name'] as String).split('/').last;
    final attachments = await api.listMemoAttachments(memoId);
    final pack = attachments
        .where((a) => a['filename'] == _attachmentFilename)
        .firstOrNull;
    if (pack == null) return;

    final bytes = await api.downloadAttachmentBytes(
      pack['name'] as String,
      _attachmentFilename,
    );
    if (bytes == null) return;
    // 内部先解密验证，成功才原子替换本地 atc.bin
    await VaultController.instance.storage.adoptRemoteAttachments(bytes);
  }
}
```

- [ ] **Step 4: VaultStorage 补两个 pullIfNewer 要用的方法**

在 `lib/services/vault/vault_storage.dart` 里追加（复用已有的 `_tryLoadIndexFrom` / `_atomicWrite` / `_applyLoaded`）：

```dart
  /// 用当前会话的主密钥窥探远端 index 的 revision，不落盘、不改内存状态。
  /// 解不开（另一个 vault 或已损坏）返回 null。
  Future<int?> peekRemoteRevision(Uint8List idxBytes) async {
    final mk = _masterKey;
    if (mk == null) return null;
    try {
      if (idxBytes.length < _headerLength + _minBodyLength) return null;
      final plain = await VaultCrypto.decryptBlob(
        mk,
        idxBytes.sublist(_headerLength),
      );
      if (plain == null) return null;
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map<String, dynamic>) return null;
      return VaultBody.fromJson(decoded).revision;
    } catch (_) {
      return null;
    }
  }

  /// 已解锁状态下用远端 index 替换本地（先验证后落盘）。
  /// 与 [adoptRemoteIndex] 的区别：这里用当前 MK，不需要重新输口令。
  Future<bool> adoptRemoteIndexWithCurrentKey(Uint8List idxBytes) async {
    final mk = _masterKey;
    if (mk == null) return false;
    try {
      if (idxBytes.length < _headerLength + _minBodyLength) return false;
      final plain = await VaultCrypto.decryptBlob(
        mk,
        idxBytes.sublist(_headerLength),
      );
      if (plain == null) return false;
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map<String, dynamic>) return false;
      final body = VaultBody.fromJson(decoded);

      await _atomicWrite(_idxFile, idxBytes);
      _passwordSlot = idxBytes.sublist(0, _keyslotLength);
      _recoverySlot = idxBytes.sublist(_keyslotLength, _headerLength);
      _entries = body.entries;
      _revision = body.revision;
      return true;
    } catch (_) {
      return false;
    }
  }
```

在 `VaultController` 里加一个转发：

```dart
  Future<bool> adoptRemoteIndex(Uint8List idxBytes, String passphrase) async {
    final ok = await _storage.adoptRemoteIndex(idxBytes, passphrase);
    if (ok) _isUnlocked.value = true;
    return ok;
  }
```

- [ ] **Step 5: 接入调用点**

`vault_controller.dart` 的 `saveEntry` / `deleteEntry` / `addAttachment` 末尾各加 `unawaited(VaultSync.push());`；`tryUnlock` 成功分支加 `unawaited(VaultSync.pullIfNewer());`。顶部加 `import 'dart:async';` 和 `import 'vault_sync.dart';`。

- [ ] **Step 6: 手动验证**

1. 配置服务端 → 创建隐私空间 → 写一条日记带一张图
2. 服务端后台确认出现一条 `IsleLog-Backup/1` 开头、`visibility=PRIVATE` 的 memo，且挂着一个 `backup.dat` 附件
3. 换一台已登录同一服务端、**从未创建过隐私空间**的设备 → 主时间线不应出现任何异常内容（验证前缀过滤生效）
4. **换机恢复**：在该设备搜索框输入 `?同一口令` 回车 → 应进入隐私空间并看到第 1 步写的日记和图片
5. 在该设备输入 `?错误口令` → 应表现为普通搜索失败，本地不应产生 `blob/idx.bin`

- [ ] **Step 7: Commit**

```bash
git add lib/services/vault/vault_sync.dart lib/services/vault/vault_storage.dart lib/services/vault/vault_controller.dart lib/services/sync/sync_service.dart lib/services/settings/settings_service.dart
git commit -m "feat: 隐私空间同步与换机恢复"
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

### Task 15: 截屏与任务切换器防护

**Files:**
- Create: `lib/services/vault/vault_screen_guard.dart`
- Modify: `android/app/src/main/kotlin/.../MainActivity.kt`
- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `lib/features/vault/vault_page.dart`

**Interfaces:**
- Consumes: 无
- Produces: `static Future<void> VaultScreenGuard.enable()` / `static Future<void> VaultScreenGuard.disable()`

**为什么不能靠锁定计时器解决**：系统的最近任务缩略图是在应用进入后台的**瞬间**截取的，和"锁定计时器设多长"完全无关——60 秒宽限期挡不住它，把 `inactive`/`hidden` 也纳入计时同样挡不住（截图发生在回调之前或同时）。这需要独立的平台机制。

不引第三方包（`flutter_windowmanager` 等维护状况不佳），自建 MethodChannel 各约 15–20 行平台代码。桌面端（macOS/Linux/Windows）无等价机制，`enable()`/`disable()` 在这些平台上直接返回。

- [ ] **Step 1: Dart 侧**

```dart
// lib/services/vault/vault_screen_guard.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 进入隐私空间时启用截屏防护，离开时关闭。
///
/// Android：FLAG_SECURE，同时屏蔽截屏和最近任务缩略图。
/// iOS：在 willResignActive 时给窗口盖一层不透明视图。
/// 桌面端无等价机制，静默跳过。
class VaultScreenGuard {
  VaultScreenGuard._();

  static const _channel = MethodChannel('islelog/screen_guard');

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  static Future<void> enable() => _invoke('enable');
  static Future<void> disable() => _invoke('disable');

  static Future<void> _invoke(String method) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (e) {
      debugPrint('[ScreenGuard] $method 失败：$e');
    }
  }
}
```

- [ ] **Step 2: Android 侧**

在 `MainActivity.kt` 里（包名以实际文件为准）：

```kotlin
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "islelog/screen_guard"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE
                    )
                    result.success(null)
                }
                "disable" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
```

- [ ] **Step 3: iOS 侧**

在 `AppDelegate.swift` 里：

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var guardEnabled = false
  private var coverView: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "islelog/screen_guard",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "enable":  self?.guardEnabled = true;  result(nil)
      case "disable": self?.guardEnabled = false; result(nil)
      default:        result(FlutterMethodNotImplemented)
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    guard guardEnabled, let window = window else { return }
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = .black
    window.addSubview(cover)
    coverView = cover
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    coverView?.removeFromSuperview()
    coverView = nil
  }
}
```

- [ ] **Step 4: 在 VaultPage 里启停**

`lib/features/vault/vault_page.dart` 的 `_VaultPageState`：

```dart
  @override
  void initState() {
    super.initState();
    VaultScreenGuard.enable();
    _loadMain();
    VaultController.instance.isUnlockedListenable.addListener(_onLockChanged);
  }

  @override
  void dispose() {
    VaultScreenGuard.disable();
    VaultController.instance.isUnlockedListenable.removeListener(_onLockChanged);
    VaultController.instance.lock();
    super.dispose();
  }
```

顶部加 `import '../../services/vault/vault_screen_guard.dart';`。

- [ ] **Step 5: 手动验证**

1. Android 真机：进入隐私空间 → 按截屏键 → 应提示"无法截屏"或截出黑屏；调出最近任务 → 缩略图应为空白
2. Android：退出隐私空间回主页 → 截屏应恢复正常
3. iOS 真机：进入隐私空间 → 上滑调出应用切换器 → 卡片应为黑屏；返回应用后内容正常显示
4. macOS（如适用）：进入隐私空间不应崩溃或报错（`_supported` 为 false，静默跳过）

- [ ] **Step 6: Commit**

```bash
git add lib/services/vault/vault_screen_guard.dart lib/features/vault/vault_page.dart android/app/src/main/kotlin ios/Runner/AppDelegate.swift
git commit -m "feat: 隐私空间截屏与任务切换器防护"
```

---

## Self-Review 记录

- **Spec 覆盖**：第 3 节（密钥/文件格式/原子写/损坏容忍）→ Task 2/5；第 4 节（三种前缀入口、仅回车触发、锁定广播、截屏防护）→ Task 7/6/8/9/15；第 5 节（数据视图 + VaultBody）→ Task 3/8；第 6 节（附件）→ Task 4/10；第 7 节（移入移出 + 级联清理）→ Task 12；第 8 节（同步 + 换机恢复 + 先验证后覆盖）→ Task 13；第 9 节（编译期开关）→ Task 14；第 10 节（存储位置）→ Task 6；第 11 节（硬删除接口）→ Task 11；第 12 节（改动清单）→ 对应各任务。全部覆盖。
- **占位符扫描**：已消除上一版 Task 13 里"pull 附件下载留白"的问题——`listMemoAttachments` / `downloadAttachmentBytes` 在 Task 11 补齐，Task 13 的 `_pullAttachmentPack` 是完整实现。全文无 TBD/TODO。
- **类型一致性**：
  - `VaultController.instance.storage`（旧名 `storageForSyncAndMigration` 已全部替换）在 Task 12/13 统一使用
  - `attachmentBytes` / `attachmentMimeType` 在 Task 5 定义、Task 6 转发、Task 10/12 使用，签名一致
  - `VaultMigrationResult` 在 Task 12 定义并在同任务的 UI 分支里穷举处理
  - `VaultSync.contentPrefix` 是 public 常量，Task 13 的 `sync_service.dart` 过滤直接引用它，不重复硬编字符串
  - `VaultBody` 在 Task 3 定义，Task 5 的 `_flushIndex`/`_tryLoadIndexFrom`/`peekRemoteRevision` 一致引用
- **已知前向依赖**：Task 7 的 `vault_entry_gate.dart` 引用 `VaultSync.recoverFromRemote`，而 `vault_sync.dart` 在 Task 13 才完整实现。Task 7 Step 3 的说明里要求先建一个返回 `false` 的桩，Task 13 再填充——这是全计划唯一一处跨任务前向依赖，已显式标注。
