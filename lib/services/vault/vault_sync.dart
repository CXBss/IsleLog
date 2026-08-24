import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../api/memos_api_service.dart';
import '../settings/settings_service.dart';
import 'vault_controller.dart';

/// 隐私空间同步。
///
/// 正文是一句人话（封面故事），两份密文作为附件上传。只在解锁期间进行。
class VaultSync {
  VaultSync._();

  /// 封面 memo 的正文首行。私版据此识别并跳过渲染。
  static const contentHeader = '📦 加密备份';

  static const _indexFilename = 'idx.dat';
  static const _packFilename = 'atc.dat';

  static bool isBackupMemoContent(String content) {
    final lines = content.split('\n');
    // 只匹配首行会误伤用户自己写的同开头 memo；封面模板固定为两行。
    return lines.length >= 2 &&
        lines[0] == contentHeader &&
        lines[1].startsWith('更新于 ');
  }

  static String _buildContent() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '$contentHeader\n更新于 ${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}';
  }

  /// 返回 (规范化 serverUrl, api)；未配置返回 null。指针按 serverUrl 隔离，
  /// 所以调用方必须同时拿到两者。
  static Future<(String, MemosApiService)?> _apiAndUrl() async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return (url, MemosApiService(baseUrl: url, token: token));
  }

  // ── 推送（3 分钟防抖 + single-flight） ────────────────────────

  static Timer? _pushTimer;
  static int _pendingRevision = -1;
  static int _lastPushedRevision = -1;
  static Future<void>? _pushInFlight;

  /// 防抖窗口。每次保存重置计时，窗口内连写多条只上传一次。
  static const _pushDebounce = Duration(minutes: 3);

  /// 记录一次待推送的改动并重置计时器。
  ///
  /// [revision] 由调用方在还持有密钥时读出并传进来——flushPush 可能在锁定之后
  /// 才执行，那时已经拿不到解密后的 revision 了。
  static void schedulePush(int revision) {
    _pendingRevision = revision;
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDebounce, () => unawaited(flushPush()));
  }

  /// 立刻把待推送的改动传上去。
  ///
  /// 必须在这两个时机调用，否则 3 分钟窗口内 App 被杀 / vault 锁定，
  /// 那次改动就永远推不上去了：
  ///   - VaultController.lock()
  ///   - App 进入 paused
  ///
  /// 刻意**不**检查 isUnlocked：推送只需要磁盘上的密文字节
  /// （readEncryptedIndexBytes 不碰主密钥），所以锁定之后依然能完成。
  ///
  /// single-flight：同一时刻最多一个 _doPush 在途；等待期间新到的 revision
  /// 会在前一个完成后被后续调用重新拾取。
  static Future<void> flushPush() {
    _pushTimer?.cancel();
    _pushTimer = null;
    if (_pendingRevision < 0 || _pendingRevision == _lastPushedRevision) {
      return Future<void>.value();
    }
    final inFlight = _pushInFlight;
    if (inFlight != null) {
      return inFlight.then((_) => flushPush());
    }
    final target = _pendingRevision;
    final future = _doPush();
    _pushInFlight = future;
    return future.then((_) {
      _lastPushedRevision = target;
    }).catchError((Object e) {
      // 不推进 _lastPushedRevision，下次 flush 仍会重试这次改动。
      debugPrint('[VaultSync] flushPush 失败，保留待推状态：$e');
    }).whenComplete(() {
      _pushInFlight = null;
      if (_pendingRevision >= 0 && _pendingRevision != _lastPushedRevision) {
        unawaited(flushPush());
      }
    });
  }

  static Future<void> _doPush() async {
    final auth = await _apiAndUrl();
    if (auth == null) return;
    final (serverUrl, api) = auth;

    final storage = VaultController.instance.storage;
    final idxBytes = await storage.readEncryptedIndexBytes();
    if (idxBytes == null) return;
    final atcBytes = await storage.readEncryptedAttachmentBytes();
    if (atcBytes == null) {
      // atc.bin 自 createVault 起就存在；缺失说明本地状态异常，不能
      // 只推 idx 并删掉远端 atc（那会丢掉整包附件）。
      debugPrint('[VaultSync] atc.bin 缺失，跳过 push');
      return;
    }

    var memoName = await SettingsService.encBackupMemoNameFor(serverUrl);
    if (memoName != null && !await _memoExists(api, memoName)) {
      // 指针失效（换机/被删）：清除后走"扫描复用或新建"。
      memoName = await _findExistingBackupMemo(api);
    }

    // 记下旧附件，等新的关联成功后再删，避免中途失败把唯一副本删掉。
    final oldAttachmentNames = <String>[];
    if (memoName != null) {
      try {
        final existing = await api.listMemoAttachments(memoName.split('/').last);
        oldAttachmentNames.addAll(existing.map((a) => a['name'] as String));
      } catch (e) {
        debugPrint('[VaultSync] 列旧附件失败（继续）：$e');
      }
    } else {
      memoName = await _findExistingBackupMemo(api);
    }

    if (memoName == null) {
      final created = await api.createMemo(
        content: _buildContent(),
        visibility: 'PRIVATE',
      );
      memoName = created['name'] as String;
    }

    // 上传新密文附件——不传 memoName：上传即自动关联会形成"新+旧并存"
    // 的中间态，崩溃后恢复下载按文件名取第一个可能拿到旧副本。
    final newNames = <String>[];
    newNames.add(await _uploadBlob(api, _indexFilename, idxBytes));
    newNames.add(await _uploadBlob(api, _packFilename, atcBytes));

    // 全量替换关联（updateMemo 的默认行为会解绑，必须走这个接口）。
    await api.setMemoAttachments(
      memoName: memoName,
      attachmentNames: newNames,
    );

    // 正文时间戳更新时必须显式带上当前附件名，否则又会被解绑。
    await api.updateMemo(
      name: memoName,
      content: _buildContent(),
      visibility: 'PRIVATE',
      attachmentNames: newNames,
    );

    await SettingsService.setEncBackupMemoName(serverUrl, memoName);

    // 新的关联稳了，再删旧资源，避免孤儿文件无限积累。
    for (final old in oldAttachmentNames) {
      if (newNames.contains(old)) continue;
      try {
        await api.deleteAttachment(old);
      } catch (e) {
        debugPrint('[VaultSync] 旧附件删除失败（忽略）：$old $e');
      }
    }
  }

  static Future<String> _uploadBlob(
    MemosApiService api,
    String filename,
    Uint8List bytes,
  ) async {
    final tmpDir = await Directory.systemTemp.createTemp('vault_sync_');
    try {
      final tmpFile = File(p.join(tmpDir.path, filename));
      await tmpFile.writeAsBytes(bytes, flush: true);
      final res = await api.uploadAttachment(
        file: tmpFile,
        filename: filename,
        // 故意不传 memoName，见 _doPush 注释。
      );
      return res['name'] as String;
    } finally {
      await tmpDir.delete(recursive: true);
    }
  }

  static Future<bool> _memoExists(MemosApiService api, String memoName) async {
    try {
      await api.listMemoAttachments(memoName.split('/').last);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _findExistingBackupMemo(MemosApiService api) async {
    try {
      final memos = await api.listAllMemos();
      for (final m in memos) {
        if (isBackupMemoContent(m['content'] as String? ?? '')) {
          final name = m['name'];
          if (name is String && name.isNotEmpty) return name;
        }
      }
    } catch (e) {
      debugPrint('[VaultSync] 扫描备份 memo 失败：$e');
    }
    return null;
  }

  static Future<bool> hasRemoteBackup() async {
    final auth = await _apiAndUrl();
    if (auth == null) return false;
    return await _findExistingBackupMemo(auth.$2) != null;
  }

  // ── 拉取（本机已有 vault，解锁后比对 revision） ──────────────

  static Future<void> pullIfNewer() async {
    if (!VaultController.instance.isUnlocked) return;
    final auth = await _apiAndUrl();
    if (auth == null) return;
    final (serverUrl, api) = auth;
    final memoName = await SettingsService.encBackupMemoNameFor(serverUrl);
    if (memoName == null) return;

    try {
      final idxBytes = await _downloadBlob(api, memoName, _indexFilename);
      if (idxBytes == null) return;

      final storage = VaultController.instance.storage;
      final remoteRevision = await storage.peekRemoteRevision(idxBytes);
      if (remoteRevision == null) return;
      if (remoteRevision <= storage.revision) {
        // 本地更新：可能是上次改动还在 3 分钟防抖窗口里 App 就被杀了。
        // 补一次推送，否则那次改动会一直留在本地不上云。
        if (remoteRevision < storage.revision) {
          schedulePush(storage.revision);
          unawaited(flushPush());
        }
        return;
      }

      // 两份文件都下载并验证后才提交；adoptRemotePairWithCurrentKey 内部
      // 先写 atc 再写 idx，atc 失败不会推进 revision，保留重试机会。
      final atcBytes = await _downloadBlob(api, memoName, _packFilename);
      if (atcBytes == null) {
        debugPrint('[VaultSync] 远端 atc.dat 缺失，不推进 idx，保留重试机会');
        return;
      }
      final ok = await storage.adoptRemotePairWithCurrentKey(idxBytes, atcBytes);
      if (!ok) {
        debugPrint('[VaultSync] 远端数据验证失败，保留本地');
      }
    } catch (e) {
      debugPrint('[VaultSync] pullIfNewer 失败：$e');
    }
  }

  // ── 换机恢复（本机无 vault，用输入的口令解远端） ──────────────

  /// Task 10 的 `?口令` 入口调用。
  ///
  /// 任何一步失败都静默返回 false，不落盘、不提示——行为与普通搜索失败一致。
  static Future<bool> recoverFromRemote(String passphrase) async {
    if (VaultController.instance.isUnlocked) return false;
    final auth = await _apiAndUrl();
    if (auth == null) return false;
    final (serverUrl, api) = auth;

    try {
      final memoName = await _findExistingBackupMemo(api);
      if (memoName == null) return false;

      final idxBytes = await _downloadBlob(api, memoName, _indexFilename);
      if (idxBytes == null) return false;
      // atc 缺失或验证失败必须整体失败：一旦先落地 idx，本地 vault 就存在了，
      // `?` 前缀失效且 revision 已推进，附件包永远不会再被重试。
      final atcBytes = await _downloadBlob(api, memoName, _packFilename);
      if (atcBytes == null) return false;

      final ok = await VaultController.instance.adoptRemotePair(
        idxBytes,
        atcBytes,
        passphrase,
      );
      if (!ok) return false;

      await SettingsService.setEncBackupMemoName(serverUrl, memoName);
      return true;
    } catch (e) {
      debugPrint('[VaultSync] recoverFromRemote 失败：$e');
      return false;
    }
  }

  // ── 共用 ──────────────────────────────────────────────────────

  static Future<Uint8List?> _downloadBlob(
    MemosApiService api,
    String memoName,
    String filename,
  ) async {
    final attachments = await api.listMemoAttachments(memoName.split('/').last);
    Map<String, dynamic>? target;
    for (final a in attachments) {
      if (a['filename'] == filename) {
        target = a;
        break;
      }
    }
    if (target == null) return null;
    return api.downloadAttachmentBytes(target['name'] as String, filename);
  }
}
