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
      final raw = await file.readAsBytes();
      final loaded = await _tryLoadIndexFrom(raw, passphrase);
      if (loaded == null) continue;
      _applyLoaded(loaded);
      // 从 .bak 恢复时立刻治愈主文件：否则后续 addAttachment 这类只写 atc
      // 的操作触发推送时，会把损坏的主 idx.bin 原样传上云端。
      // 注意用 _healFile 而不是 _atomicWrite——_atomicWrite 会把损坏的主文件
      // 轮转成新的 .bak，反而把刚才救命的完好 .bak 覆盖掉。
      if (file.path != _idxFile.path) {
        await _healFile(_idxFile, raw);
      }
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
      // 恢复码槽只在候选长度恰为 24 时才试——恢复码是固定 24 位、固定字母表
      // 生成的，长度不符的输入不可能是恢复码。少了这个判断，每次口令输错都要
      // 白跑第二次 32MB 的 Argon2id。
      if (mk == null && credential.length == VaultCrypto.recoveryCodeLength) {
        mk = await VaultCrypto.tryUnwrapMasterKey(recSlot, credential);
      }
      if (mk == null) return null;

      final plain = await VaultCrypto.decryptBlob(mk, raw.sublist(_headerLength));
      if (plain == null) return null;

      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map<String, dynamic>) return null;
      final body = VaultBody.fromJson(decoded);
      // 不支持未来版本。绝不回退 .bak 旧版继续用——那会在下次保存时覆盖新版本。
      if (body.version != 1) return null;

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
        // 与 idx 同理：从 bak 恢复时治愈主文件，且不破坏好 bak。
        if (file.path != _atcFile.path) {
          await _healFile(_atcFile, await file.readAsBytes());
        }
        return;
      } catch (_) {
        continue;
      }
    }
    _attachments = [];
  }

  // ── 换机恢复 / 远端采用：先验证，后落盘 ────────────────────────

  /// 用远端拉回的 idx.bin 恢复本地 vault（新设备场景，仅单测与简单路径使用）。
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

  /// 用当前会话的主密钥窥探远端 index 的 revision，不落盘、不改内存状态。
  /// 解不开（是另一个 vault，或已损坏）返回 null。
  Future<int?> peekRemoteRevision(Uint8List idxBytes) async {
    final mk = _masterKey;
    if (mk == null) return null;
    final decoded = await _decryptBodyForCurrentKey(idxBytes, mk);
    if (decoded == null) return null;
    final body = VaultBody.fromJson(decoded);
    if (body.version != 1) return null;
    return body.revision;
  }

  /// 已解锁状态下整体采用远端 idx + atc（先验证，后提交）。
  ///
  /// 提交顺序：先 atc、后 idx（idx 是提交点）。任一文件在内存中验证失败就
  /// 返回 false 且不落任何字节；如果先提交 idx 再拉 atc，atc 失败后 revision
  /// 已经前进，之后永远不会重试，条目引用的附件字节就永久缺失。
  Future<bool> adoptRemotePairWithCurrentKey(
    Uint8List idxBytes,
    Uint8List? atcBytes,
  ) async {
    final mk = _masterKey;
    if (mk == null) return false;
    try {
      final idxDecoded = await _decryptBodyForCurrentKey(idxBytes, mk);
      if (idxDecoded == null) return false;
      final body = VaultBody.fromJson(idxDecoded);
      if (body.version != 1) return false;

      List<VaultAttachment> attachments = _attachments;
      if (atcBytes != null) {
        final atcPlain = await VaultCrypto.decryptBlob(mk, atcBytes);
        if (atcPlain == null) return false;
        attachments = VaultContainerCodec.decodeAttachments(atcPlain);
        await _atomicWrite(_atcFile, atcBytes);
      }

      await _atomicWrite(_idxFile, idxBytes);
      _passwordSlot = idxBytes.sublist(0, _keyslotLength);
      _recoverySlot = idxBytes.sublist(_keyslotLength, _headerLength);
      _entries = body.entries;
      _revision = body.revision;
      _attachments = attachments;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 换机恢复：口令解 keyslot + 两份文件全部在内存验证通过后才落盘。
  /// 同样先 atc 后 idx；atc 缺失/验证失败整体失败，不创建本地 vault——
  /// 否则本地 vault 一存在，`?` 前缀失效且 revision 已推进，附件包再也不会重试。
  Future<bool> adoptRemotePair(
    Uint8List idxBytes,
    Uint8List? atcBytes,
    String passphrase,
  ) async {
    final loaded = await _tryLoadIndexFrom(idxBytes, passphrase);
    if (loaded == null || atcBytes == null) return false;
    try {
      final atcPlain = await VaultCrypto.decryptBlob(loaded.mk, atcBytes);
      if (atcPlain == null) return false;
      final attachments = VaultContainerCodec.decodeAttachments(atcPlain);

      if (!await dir.exists()) await dir.create(recursive: true);
      await _atomicWrite(_atcFile, atcBytes);
      await _atomicWrite(_idxFile, idxBytes);
      _applyLoaded(loaded);
      _attachments = attachments;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _decryptBodyForCurrentKey(
    Uint8List idxBytes,
    SecretKey mk,
  ) async {
    if (idxBytes.length < _headerLength + _minBodyLength) return null;
    final plain = await VaultCrypto.decryptBlob(
      mk,
      idxBytes.sublist(_headerLength),
    );
    if (plain == null) return null;
    final decoded = jsonDecode(utf8.decode(plain));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  // ── 条目读写 ──────────────────────────────────────────────────

  Future<void> saveEntry(VaultEntry entry) async {
    _requireKey();
    _entries = [..._entries.where((e) => e.id != entry.id), entry];
    await _flushIndex();
  }

  Future<void> deleteEntry(String id) async {
    _requireKey();
    final target = _findEntry(_entries, id);
    _entries = _entries.where((e) => e.id != id).toList();
    await _flushIndex();
    if (target != null && target.attachmentIds.isNotEmpty) {
      _attachments = _attachments
          .where((a) => !target.attachmentIds.contains(a.id))
          .toList();
      await _flushAttachments();
    }
  }

  // 不使用 Iterable.firstOrNull：它来自 dart:collection 的扩展，本文件不引入
  // 额外依赖。手工循环在任何 SDK 下都成立。
  static T? _firstWhereOrNull<T>(List<T> list, bool Function(T) test) {
    for (final item in list) {
      if (test(item)) return item;
    }
    return null;
  }

  static VaultEntry? _findEntry(List<VaultEntry> list, String id) =>
      _firstWhereOrNull(list, (e) => e.id == id);

  static VaultAttachment? _findAttachment(List<VaultAttachment> list, String id) =>
      _firstWhereOrNull(list, (a) => a.id == id);

  Uint8List? attachmentBytes(String id) =>
      _findAttachment(_attachments, id)?.bytes;

  String? attachmentMimeType(String id) =>
      _findAttachment(_attachments, id)?.mimeType;

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

  /// 用已知完好的字节修复主文件，不旋转 .bak——调用场景是从 .bak 恢复成功，
  /// 此时 .bak 是唯一的好副本，绝不能被损坏的主文件替换掉。
  Future<void> _healFile(File target, List<int> bytes) async {
    final tmp = File('${target.path}.heal');
    await tmp.writeAsBytes(bytes, flush: true);
    if (await target.exists()) await target.delete();
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
