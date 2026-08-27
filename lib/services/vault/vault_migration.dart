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
          for (final id in attachmentIds) {
            await VaultController.instance.storage.removeAttachment(id);
          }
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
      if (api != null && memo.memosName != null) {
        try {
          await api.deleteMemo(memo.memosName!, hard: true);
        } catch (e) {
          if (!_isNotFound(e)) {
            debugPrint('[VaultMigration] 远端 memo 删除失败：$e');
            return VaultMigrationResult.failed;
          }
          debugPrint('[VaultMigration] 远端 memo 已不存在（404），按已删除继续');
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
