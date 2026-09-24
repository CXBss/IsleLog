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
import '../sync/sync_service.dart';
import 'vault_controller.dart';

enum VaultMigrationResult { ok, blockedPendingSync, blockedConflict, failed }

/// 远端硬删的结论，见 [VaultMigration._hardDeleteRemote]。
enum _RemoteDeleteOutcome {
  /// 远端确认已无这条日记（删除成功，或本来就不存在）。
  gone,

  /// 远端确认删除没生效（拿到了 HTTP 错误响应），明文一定还在。
  notDeleted,

  /// 无法确认（网络中断且复核也失败）。此时保留 vault 副本，不冒丢日记的风险。
  unknown,
}

/// 普通日记 ⇄ 隐私空间之间的移入/移出。
class VaultMigration {
  VaultMigration._();

  /// 普通日记 → vault。
  ///
  /// 两道并发防护：
  /// 1. 前置拒绝 pending/conflict——pending 可能正在被后台推送，conflict 的
  ///    远端版本会被 hard delete 丢弃，等于替用户做了不可逆决定；
  /// 2. 整个过程走 SyncService 的任务队列串行化——关掉第 1 条关不掉的窗口：
  ///    一次 syncAll() 可能已拉到远端列表，我这边远端硬删+本地硬删之后，
  ///    _applyRemoteMemo 拿着旧列表又会把它建回来。
  static Future<VaultMigrationResult> moveIntoVault(MemoEntry memo) async {
    if (memo.syncStatus == SyncStatus.pending) {
      return VaultMigrationResult.blockedPendingSync;
    }
    if (memo.syncStatus == SyncStatus.conflict) {
      return VaultMigrationResult.blockedConflict;
    }
    if (!VaultController.instance.isUnlocked) {
      return VaultMigrationResult.failed;
    }
    return SyncService.runExclusive(() => _moveIntoVaultLocked(memo));
  }

  static Future<VaultMigrationResult> _moveIntoVaultLocked(
    MemoEntry memo,
  ) async {
    try {
      final url = await SettingsService.serverUrl;
      final token = await SettingsService.accessToken;
      final configured =
          url != null && url.isNotEmpty && token != null && token.isNotEmpty;
      final api = configured
          ? MemosApiService(baseUrl: url, token: token)
          : null;

      // 已同步到远端的条目，服务器必须可用——否则单方面删本地等于本地藏起来、
      // 远端明文还在，违背移入的本意。
      if (memo.memosName != null && api == null) {
        debugPrint('[VaultMigration] 已同步条目但服务器未配置，中止移入');
        return VaultMigrationResult.failed;
      }

      // ── 1. 收集附件字节，写进 vault ──
      final attachmentIds = <String>[];
      final resolved = <AttachmentInfo>[];
      for (final att in memo.attachments) {
        var local = att;
        final missing =
            local.localPath == null || !File(local.localPath!).existsSync();
        if (missing && api != null) {
          local = await AttachmentService.downloadToLocal(att, url!, token!);
        }
        if (local.localPath == null || !File(local.localPath!).existsSync()) {
          debugPrint('[VaultMigration] 附件字节取不到，中止移入：${local.filename}');
          await _rollbackVaultWrite(attachmentIds: attachmentIds);
          return VaultMigrationResult.failed;
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
        // 元数据一并带过来，否则移入等于把天气/心情/位置悄悄抹掉
        location: memo.location,
        latitude: memo.latitude,
        longitude: memo.longitude,
        weatherJson: memo.weatherJson,
        mood: memo.mood,
      );
      await VaultController.instance.saveEntry(entry);

      // ── 2. 远端硬删除 ──
      // 顺序：先删 memo（hard=true 已级联附件），404 视为已删；再对旧附件
      // 资源做 best-effort 清理。反过来时 memo 删除失败会留下半残记录。
      //
      // 这一步还要决定"删失败之后怎么办"：vault 副本在上面已经写好了。
      // 只有在**确认远端明文还在**时才允许撤销它，见 [_hardDeleteRemote]。
      if (api != null && memo.memosName != null) {
        final outcome = await _hardDeleteRemote(api, memo.memosName!);
        if (outcome != _RemoteDeleteOutcome.gone) {
          if (outcome == _RemoteDeleteOutcome.notDeleted) {
            // 远端明文确认还在 ⇒ 撤掉刚写进 vault 的那一份。否则这次"移入"
            // 只是把明文在本地藏起来，云端那份照旧存在，违背移入的本意。
            await _rollbackVaultWrite(
              entryId: entry.id,
              attachmentIds: attachmentIds,
            );
          } else {
            // 结果未知：保留 vault 副本。宁可多留一份密文，也不能在
            // "远端其实已经删成功"的情况下把唯一副本丢掉（详见方法注释）。
            debugPrint(
              '[VaultMigration] 远端删除结果未知，保留 vault 副本 ${entry.id} 并报失败',
            );
          }
          return VaultMigrationResult.failed;
        }
        for (final att in memo.attachments) {
          if (att.remoteResName == null) continue;
          try {
            await api.deleteAttachment(att.remoteResName!);
          } catch (e) {
            debugPrint('[VaultMigration] 远端附件清理失败（忽略）：$e');
          }
        }
      }

      // ── 3. 本地级联清理 ──
      for (final att in resolved) {
        if (att.localPath != null) {
          await AttachmentService.deleteLocal(att.localPath!);
        }
      }
      final comments = await DatabaseService.getCommentsByMemoId(memo.id);
      for (final c in comments) {
        await DatabaseService.hardDeleteComment(c.id);
      }
      await DatabaseService.removeMemoFromAllThreads(memo.id);
      // TagStat 缓存重算——主页抽屉优先读缓存，残留标签名会泄漏。
      final counts = await DatabaseService.getAllTagCounts();
      await DatabaseService.saveTagStats(counts);
      await DatabaseService.hardDelete(memo.id);

      return VaultMigrationResult.ok;
    } catch (e) {
      debugPrint('[VaultMigration] 移入失败：$e');
      return VaultMigrationResult.failed;
    }
  }

  static bool _isNotFound(Object e) =>
      e is MemosApiException && e.statusCode == 404;

  /// 硬删远端 memo 的三种结论。
  ///
  /// 为什么不是 try/catch 一把梭：客户端移入隐私空间是"**先写 vault、再删远端**"。
  /// 若远端其实已经删成功、而客户端因超时误判成失败并撤销 vault 副本，那么本地
  /// 这条日记会在下一次同步时被 changelog 的 DELETE 记录连带物理删除——vault 和
  /// 本地同时没有，等于永久丢日记。因此**只有确认远端还在时才允许撤销**。
  static Future<_RemoteDeleteOutcome> _hardDeleteRemote(
    MemosApiService api,
    String memosName,
  ) async {
    try {
      await api.deleteMemo(memosName, hard: true);
      return _RemoteDeleteOutcome.gone;
    } on MemosApiException catch (e) {
      if (_isNotFound(e)) {
        // 远端本来就没有（例如用户重复点了一次）：目标状态已达成。
        debugPrint('[VaultMigration] 远端 memo 已不存在（404），按已删除继续');
        return _RemoteDeleteOutcome.gone;
      }
      if (e.statusCode != null) {
        // 拿到了 HTTP 响应 ⇒ 请求确实到达服务端且被拒绝（403 / 500 等）。
        // 服务端 HardDelete 是单事务，失败即未提交，远端明文一定还在。
        debugPrint('[VaultMigration] 远端 memo 删除被拒绝（${e.statusCode}）：$e');
        return _RemoteDeleteOutcome.notDeleted;
      }
      // 没有 HTTP 响应（超时 / 断连）：删除可能已经生效，必须复核。
      return _verifyRemoteGone(api, memosName);
    }
  }

  /// 网络层失败后的复核：查一次远端，判断 memo 那行是否还在。
  ///
  /// 注意服务端 `GetMemo`（handler/memo.go:197）在 memos 表查不到该 id 时会回退去
  /// comments 表里找同 id 的记录并返回 200——那是**评论**，不是这条日记。反过来
  /// 说，只要返回的不是这条 memo 本身，就证明 memos 表里已经没有它了，删除其实
  /// 成功了。这正是我们要的判断依据（两边都存 id，跨表撞号是常见情况）。
  static Future<_RemoteDeleteOutcome> _verifyRemoteGone(
    MemosApiService api,
    String memosName,
  ) async {
    final id = memosName.split('/').last;
    try {
      final data = await api.getMemo(id);
      if (data['name'] == memosName) {
        debugPrint('[VaultMigration] 复核：远端 memo 仍在，按删除失败处理');
        return _RemoteDeleteOutcome.notDeleted;
      }
      debugPrint(
        '[VaultMigration] 复核：远端 memo 行已不存在（返回 ${data['name']}），'
        '按已删除继续',
      );
      return _RemoteDeleteOutcome.gone;
    } on MemosApiException catch (e) {
      if (_isNotFound(e)) {
        debugPrint('[VaultMigration] 复核：远端 memo 已不存在（404）');
        return _RemoteDeleteOutcome.gone;
      }
      debugPrint('[VaultMigration] 复核失败，无法确认远端是否已删：$e');
      return _RemoteDeleteOutcome.unknown;
    }
  }

  /// 撤掉刚写进 vault 的条目与附件，让状态回到"什么都没发生"。
  ///
  /// 尽力而为：回滚本身失败只留日志，不改变返回值——真正的失败原因仍然是远端
  /// 没删掉，返回值不该被回滚的失败改写。
  static Future<void> _rollbackVaultWrite({
    String? entryId,
    List<String> attachmentIds = const [],
  }) async {
    if (entryId != null) {
      try {
        await VaultController.instance.deleteEntry(entryId);
      } catch (e) {
        debugPrint('[VaultMigration] 回滚 vault 条目失败（$entryId）：$e');
      }
    }
    for (final id in attachmentIds) {
      try {
        await VaultController.instance.storage.removeAttachment(id);
      } catch (e) {
        debugPrint('[VaultMigration] 回滚 vault 附件失败（$id）：$e');
      }
    }
  }

  /// vault → 普通日记。附件字节完整还原，不静默销毁。
  static Future<VaultMigrationResult> moveOutOfVault(VaultEntry entry) async {
    if (!VaultController.instance.isUnlocked) {
      return VaultMigrationResult.failed;
    }

    try {
      // ── 1. 附件先还原成正常附件（经临时文件过渡给 AttachmentService） ──
      final restored = <AttachmentInfo>[];
      Directory? tmpDir;
      try {
        for (final attId in entry.attachmentIds) {
          final bytes = VaultController.instance.attachmentBytes(attId);
          final mime = VaultController.instance.attachmentMimeType(attId);
          // 与移入同一原则：条目引用的附件字节缺失就整体中止。
          if (bytes == null) {
            throw StateError('vault 附件字节缺失：$attId');
          }

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
      } finally {
        // 临时明文文件用完立刻删
        await tmpDir?.delete(recursive: true);
      }

      // ── 2. 建主库条目 ──
      final memo = MemoEntry()
        ..content = entry.content
        ..createdAt = entry.createdAt
        ..updatedAt = DateTime.now()
        ..attachments = restored
        ..location = entry.location
        ..latitude = entry.latitude
        ..longitude = entry.longitude
        ..weatherJson = entry.weatherJson
        ..mood = entry.mood;
      await DatabaseService.saveMemo(memo);

      // ── 3. 全部成功后才从 vault 移除 ──
      await VaultController.instance.deleteEntry(entry.id);
      return VaultMigrationResult.ok;
    } catch (e) {
      debugPrint('[VaultMigration] 移出失败：$e');
      return VaultMigrationResult.failed;
    }
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
