import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/database/database_service.dart';
import '../../data/models/attachment_info.dart';
import '../../data/models/comment_entry.dart';
import '../../data/models/memo_entry.dart';
import '../../shared/constants/app_constants.dart';
import '../api/memos_api_service.dart';
import '../attachment/attachment_service.dart';
import '../settings/settings_service.dart';

/// 同步操作结果
///
/// 由 [SyncService.syncAll] 返回，包含推送/拉取数量和错误信息。
class SyncResult {
  /// 本次推送到远端的条目数
  final int pushed;

  /// 本次从远端拉取到本地的条目数
  final int pulled;

  /// 本次因远端已删除而本地物理删除的条目数（仅全量同步时非零）
  final int deleted;

  /// 错误信息（null 表示同步成功）
  final String? error;

  const SyncResult({this.pushed = 0, this.pulled = 0, this.deleted = 0, this.error});

  /// true 表示本次同步没有发生错误
  bool get success => error == null;

  @override
  String toString() {
    if (!success) return '同步失败：$error';
    final parts = <String>['推送 $pushed 条', '拉取 $pulled 条'];
    if (deleted > 0) parts.add('删除 $deleted 条');
    return '同步完成：${parts.join('，')}';
  }
}

/// 离线优先双向同步引擎
///
/// ## 同步策略
///
/// ### Push（本地 → 远端）
/// 遍历所有 `syncStatus == pending` 的条目：
/// - `isDeleted == true`：若有远端 ID 则删除远端，再本地物理删除
/// - `memosName == null`（新建）：推送到远端，将返回的资源名写回本地
/// - 其他：更新远端内容
///
/// ### Pull（远端 → 本地）
/// - 增量同步：优先使用 `lastSyncTime` 过滤（仅拉取有更新的条目）
/// - 回退全量：服务端不支持 filter 时全量拉取
/// - 合并规则：
///   - 远端有、本地无 → 新增到本地
///   - 本地 `synced` → 覆盖为远端最新
///   - 本地 `pending`（双方都改了） → 标记 `conflict`，保留本地版本，等用户处理
class SyncService {
  SyncService._();

  // ── 公开接口 ──────────────────────────────────────────────────

  /// 增量双向同步（先 Push 再增量 Pull）
  ///
  /// Pull 阶段仅拉取自上次同步以来有变化的条目，不做远端删除检测。
  /// 如未配置服务器，直接返回错误结果而不发起任何网络请求。
  /// 同步成功后自动更新 [SettingsService.lastSyncTime]。
  static Future<SyncResult> syncAll() async {
    debugPrint('[Sync] syncAll（增量）开始');
    return _sync(full: false);
  }

  /// 全量双向同步（先 Push 再全量 Pull + 远端删除检测）
  ///
  /// Pull 阶段忽略 lastSyncTime，拉取所有条目，
  /// 并将本地存在但远端已不存在的已同步条目物理删除。
  /// 适合服务器迁移、手动清理后恢复一致性等场景。
  static Future<SyncResult> syncFull() async {
    debugPrint('[Sync] syncFull（全量）开始');
    return _sync(full: true);
  }

  /// 内部同步实现
  ///
  /// [full]：true = 全量拉取 + 删除检测；false = 增量拉取
  static Future<SyncResult> _sync({required bool full}) async {
    // 前置检查：确保服务器已配置
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      debugPrint('[Sync] _sync 终止：未配置服务器');
      return const SyncResult(error: AppStrings.syncNoConfig);
    }

    final api = MemosApiService(baseUrl: url, token: token);
    try {
      final pushed = await _pushPending(api, url, token);
      // push 完成后、pull 开始前记录时间：
      // 既避免把刚推上去的条目再拉回来，又不漏掉 push 期间远端其他人的修改
      final syncTime = DateTime.now();
      final (pulled, deleted, memosWithComments) =
          await _pullUpdates(api, url, full: full);
      // 对 relations 中标记有评论的日记拉取评论（全量和增量都执行）
      if (memosWithComments.isNotEmpty) {
        await _pullCommentsBatch(api, memosWithComments);
      }
      await SettingsService.setLastSyncTime(syncTime);
      final result = SyncResult(pushed: pushed, pulled: pulled, deleted: deleted);
      debugPrint('[Sync] _sync 完成（full=$full）：$result');
      return result;
    } on MemosApiException catch (e) {
      debugPrint('[Sync] _sync API 异常：${e.message}');
      return SyncResult(error: e.message);
    } catch (e) {
      debugPrint('[Sync] _sync 未知异常：$e');
      return SyncResult(error: e.toString());
    }
  }

  /// 仅推送本地 pending 条目（保存日记后的后台静默推送）
  ///
  /// 静默失败：遇到任何错误只打印日志，不抛出异常，
  /// 保持 pending 状态等待下次手动同步。
  static Future<void> pushPendingBackground() async {
    debugPrint('[Sync] pushPendingBackground 开始');
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      debugPrint('[Sync] pushPendingBackground 终止：未配置服务器');
      return;
    }

    final api = MemosApiService(baseUrl: url, token: token);
    try {
      final count = await _pushPending(api, url, token);
      debugPrint('[Sync] pushPendingBackground 完成，推送 $count 条');
    } catch (e) {
      // 静默失败，保持 pending 状态，等待下次手动同步
      debugPrint('[Sync] pushPendingBackground 静默失败：$e');
    }
  }

  // ── Push（本地 pending → 远端）───────────────────────────────

  /// 将所有 pending 条目推送到远端
  ///
  /// 单条失败不中断循环，该条保持 pending，等待下次重试。
  /// 返回成功推送的条目数。
  static Future<int> _pushPending(
      MemosApiService api, String url, String token) async {
    final pendingList = await DatabaseService.getPendingSyncMemos();
    debugPrint('[Sync] _pushPending: 待推送 ${pendingList.length} 条');
    int count = 0;

    for (final memo in pendingList) {
      try {
        if (memo.isDeleted) {
          // ── 处理软删除：远端有 ID 则先删远端，再本地物理删除 ──
          if (memo.memosName != null) {
            debugPrint('[Sync] 删除远端 memo: ${memo.memosName}');
            await api.deleteMemo(memo.memosName!);
          }
          await DatabaseService.hardDelete(memo.id);
          debugPrint('[Sync] 本地物理删除完成 id=${memo.id}');
        } else if (memo.isArchived) {
          // ── 处理归档 ──
          if (memo.memosName != null) {
            debugPrint('[Sync] 归档远端 memo: ${memo.memosName}');
            await api.archiveMemo(memo.memosName!);
          }
          memo
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveMemo(memo, skipTimestamp: true);
          debugPrint('[Sync] 归档成功 id=${memo.id}');
        } else {
          // ── 补传离线附件 ──
          await _uploadPendingAttachments(api, memo, url, token);

          // 收集已上传的附件资源名
          final attachmentNames = memo.attachments
              .where((a) => a.remoteResName != null)
              .map((a) => a.remoteResName!)
              .toList();

          if (memo.memosName == null) {
            // ── 处理新建 ──
            debugPrint('[Sync] 新建远端 memo id=${memo.id}，附件 ${attachmentNames.length} 个');
            final remoteData = await api.createMemo(
              content: memo.content,
              attachmentNames: attachmentNames,
              createTime: memo.createdAt,
              locationPlaceholder: memo.location,
              latitude: memo.latitude,
              longitude: memo.longitude,
            );
            memo
              ..memosName = remoteData['name'] as String?
              ..syncStatus = SyncStatus.synced
              ..lastSyncAt = DateTime.now();
            await DatabaseService.saveMemo(memo, skipTimestamp: true);
            // 同步置顶状态
            if (memo.isPinned && memo.memosName != null) {
              await api.pinMemo(memo.memosName!);
            }
            debugPrint('[Sync] 新建成功，memosName=${memo.memosName}');
          } else {
            // ── 处理更新 ──
            debugPrint('[Sync] 更新远端 memo: ${memo.memosName}，附件 ${attachmentNames.length} 个');
            await api.updateMemo(
              name: memo.memosName!,
              content: memo.content,
              attachmentNames: attachmentNames,
              createTime: memo.createdAt,
              locationPlaceholder: memo.location,
              latitude: memo.latitude,
              longitude: memo.longitude,
            );
            // 同步置顶状态
            if (memo.isPinned) {
              await api.pinMemo(memo.memosName!);
            } else {
              await api.unpinMemo(memo.memosName!);
            }
            memo
              ..syncStatus = SyncStatus.synced
              ..lastSyncAt = DateTime.now();
            await DatabaseService.saveMemo(memo, skipTimestamp: true);
            debugPrint('[Sync] 更新成功，memosName=${memo.memosName}');
          }
        }
        count++;
      } catch (e) {
        // 单条失败不中断整体流程
        debugPrint('[Sync] 单条推送失败 id=${memo.id}: $e（保持 pending）');
      }
    }

    debugPrint('[Sync] _pushPending 完成，成功推送 $count 条');

    // ── 推送评论 ──
    count += await _pushPendingComments(api);
    return count;
  }

  /// 推送所有 pending 评论到远端
  static Future<int> _pushPendingComments(MemosApiService api) async {
    final pendingComments = await DatabaseService.getPendingSyncComments();
    debugPrint('[Sync] _pushPendingComments: 待推送 ${pendingComments.length} 条');
    int count = 0;

    for (final comment in pendingComments) {
      try {
        if (comment.isDeleted) {
          if (comment.memosName != null) {
            await api.deleteMemo(comment.memosName!);
          }
          await DatabaseService.hardDeleteComment(comment.id);
          debugPrint('[Sync] 评论远端删除完成 id=${comment.id}');
        } else if (comment.memosName == null) {
          // 新建评论：需要父 memo 的 memosName
          final parentName = comment.parentMemosName;
          if (parentName == null) {
            debugPrint('[Sync] 评论缺少 parentMemosName，跳过 id=${comment.id}');
            continue;
          }
          final data = await api.createMemoComment(
            memoName: parentName,
            content: comment.content,
          );
          comment
            ..memosName = data['name'] as String?
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveComment(comment, skipTimestamp: true);
          debugPrint('[Sync] 评论新建成功 memosName=${comment.memosName}');
        } else {
          // 更新评论（同普通 memo）
          await api.updateMemo(
            name: comment.memosName!,
            content: comment.content,
          );
          comment
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveComment(comment, skipTimestamp: true);
          debugPrint('[Sync] 评论更新成功 memosName=${comment.memosName}');
        }
        count++;
      } catch (e) {
        debugPrint('[Sync] 评论推送失败 id=${comment.id}: $e（保持 pending）');
      }
    }
    return count;
  }

  // ── Pull（远端 → 本地）──────────────────────────────────────

  /// 从远端拉取更新并合并到本地。
  ///
  /// [full]：true = 全量拉取 + 远端删除检测；false = 增量拉取（基于 lastSyncTime 过滤）。
  /// 增量模式下若服务端不支持 filter，静默降级为全量拉取（但不做删除检测）。
  /// 返回 (合并条目数, 删除条目数, 有评论的日记 memosName 集合)。
  /// 评论集合由 relations[type=COMMENT] 提取，调用方负责后续拉取评论。
  static Future<(int, int, Set<String>)> _pullUpdates(
      MemosApiService api, String baseUrl,
      {bool full = false}) async {
    String? filter;
    if (!full) {
      final lastSync = await SettingsService.lastSyncTime;
      if (lastSync != null) {
        final ts = lastSync.millisecondsSinceEpoch ~/ 1000;
        filter = 'updated_ts >= $ts';
        debugPrint('[Sync] _pullUpdates 增量拉取，filter=$filter');
      } else {
        debugPrint('[Sync] _pullUpdates 首次同步，全量拉取');
      }
    } else {
      debugPrint('[Sync] _pullUpdates 全量拉取（full=true）');
    }

    // 同时拉取 NORMAL 和 ARCHIVED 两个状态
    List<Map<String, dynamic>> normalMemos;
    List<Map<String, dynamic>> archivedMemos;
    try {
      normalMemos = await api.listAllMemos(filter: filter, state: 'NORMAL');
      archivedMemos = await api.listAllMemos(filter: filter, state: 'ARCHIVED');
    } catch (e) {
      debugPrint('[Sync] filter 不支持，回退全量拉取：$e');
      normalMemos = await api.listAllMemos(state: 'NORMAL');
      archivedMemos = await api.listAllMemos(state: 'ARCHIVED');
    }
    debugPrint('[Sync] 远端 NORMAL=${normalMemos.length} ARCHIVED=${archivedMemos.length}');

    final remoteNames = <String>{};
    final memosWithComments = <String>{};
    int pulled = 0;
    int deleted = 0;

    Future<void> processList(List<Map<String, dynamic>> list, bool archived) async {
      for (final data in list) {
        final remoteName = data['name'] as String? ?? '';
        if (remoteName.isEmpty) continue;
        remoteNames.add(remoteName);
        pulled += await _applyRemoteMemo(data, baseUrl, archived: archived);
        // 从 relations 收集有评论的日记：relatedMemo 是父日记
        for (final rel in (data['relations'] as List<dynamic>? ?? [])) {
          final relMap = rel as Map<String, dynamic>;
          if (relMap['type'] == 'COMMENT') {
            final parentName =
                (relMap['relatedMemo'] as Map<String, dynamic>?)?['name'] as String?;
            if (parentName != null && parentName.isNotEmpty) {
              memosWithComments.add(parentName);
            }
          }
        }
      }
    }

    await processList(normalMemos, false);
    await processList(archivedMemos, true);

    // 远端删除检测：仅全量模式执行
    if (full) {
      final allLocal = await _getAllSyncedWithMemosName();
      for (final local in allLocal) {
        if (!remoteNames.contains(local.memosName)) {
          debugPrint('[Sync] 远端已删除，本地同步删除 id=${local.id} memosName=${local.memosName}');
          await DatabaseService.hardDelete(local.id);
          deleted++;
        }
      }
    }

    debugPrint(
        '[Sync] _pullUpdates 完成（full=$full），拉取 $pulled 条，删除 $deleted 条，有评论日记 ${memosWithComments.length} 篇');
    return (pulled, deleted, memosWithComments);
  }

  /// 将单条远端 memo 数据应用到本地，返回 1（有变化）或 0
  static Future<int> _applyRemoteMemo(
    Map<String, dynamic> data,
    String baseUrl, {
    required bool archived,
  }) async {
    final remoteName = data['name'] as String;

    final localMemo = await DatabaseService.getMemoByMemosName(remoteName);

    if (localMemo == null) {
      final newMemo = _buildFromRemote(data, baseUrl);
      newMemo.isArchived = archived;
      await DatabaseService.saveMemo(newMemo, skipTimestamp: true);
      debugPrint('[Sync] 新增本地 memo: $remoteName archived=$archived');
      unawaited(_downloadAttachments(newMemo, baseUrl));
      return 1;
    } else if (localMemo.syncStatus == SyncStatus.synced) {
      _applyRemoteData(localMemo, data, baseUrl);
      localMemo.isArchived = archived;
      await DatabaseService.saveMemo(localMemo, skipTimestamp: true);
      debugPrint('[Sync] 更新本地 memo: $remoteName archived=$archived');
      unawaited(_downloadAttachments(localMemo, baseUrl));
      return 1;
    } else if (localMemo.syncStatus == SyncStatus.pending) {
      debugPrint('[Sync] 检测到冲突，标记 conflict: $remoteName');
      localMemo.syncStatus = SyncStatus.conflict;
      await DatabaseService.saveMemo(localMemo, skipTimestamp: true);
    }
    return 0;
  }

  /// 将单条远端评论数据合并到本地 CommentEntry
  static Future<int> _applyRemoteComment(
    Map<String, dynamic> data,
    String parentMemosName,
  ) async {
    final remoteName = data['name'] as String;
    final local = await DatabaseService.getCommentByMemosName(remoteName);
    final creator = data['creator'] as String? ?? '';

    if (local == null) {
      final comment = CommentEntry()
        ..memosName = remoteName
        ..parentMemosName = parentMemosName
        ..content = data['content'] as String? ?? ''
        ..creatorName = creator
        ..syncStatus = SyncStatus.synced
        ..lastSyncAt = DateTime.now();
      final ct = data['createTime'] as String?;
      if (ct != null) comment.createdAt = DateTime.parse(ct).toLocal();
      final ut = data['updateTime'] as String?;
      if (ut != null) comment.updatedAt = DateTime.parse(ut).toLocal();
      await DatabaseService.saveComment(comment, skipTimestamp: true);
      debugPrint('[Sync] 新增评论 $remoteName parent=$parentMemosName');
      return 1;
    } else if (local.syncStatus == SyncStatus.synced) {
      local
        ..content = data['content'] as String? ?? ''
        ..creatorName = creator
        ..parentMemosName = parentMemosName
        ..syncStatus = SyncStatus.synced
        ..lastSyncAt = DateTime.now();
      final ut = data['updateTime'] as String?;
      if (ut != null) local.updatedAt = DateTime.parse(ut).toLocal();
      await DatabaseService.saveComment(local, skipTimestamp: true);
      debugPrint('[Sync] 更新评论 $remoteName');
      return 1;
    } else if (local.syncStatus == SyncStatus.pending) {
      debugPrint('[Sync] 评论冲突 $remoteName，标记 conflict');
      local.syncStatus = SyncStatus.conflict;
      await DatabaseService.saveComment(local, skipTimestamp: true);
    }
    return 0;
  }

  /// 拉取并合并单篇日记的远端评论（供详情页进入时调用）
  ///
  /// 静默失败：网络不可用或服务器未配置时不抛出异常。
  static Future<void> syncMemoComments(MemoEntry memo) async {
    if (memo.memosName == null) return; // 未同步的日记没有远端评论
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) return;

    final api = MemosApiService(baseUrl: url, token: token);
    try {
      await _fetchAndApplyComments(api, memo.memosName!);
      debugPrint('[Sync] syncMemoComments 完成 memo=${memo.memosName}');
    } catch (e) {
      debugPrint('[Sync] syncMemoComments 静默失败 memo=${memo.memosName}: $e');
    }
  }

  /// 批量拉取指定日记的评论（由 _pullUpdates 提取的有评论日记集合驱动）
  static Future<void> _pullCommentsBatch(
      MemosApiService api, Set<String> memoNames) async {
    debugPrint('[Sync] _pullCommentsBatch: ${memoNames.length} 篇日记需拉取评论');
    for (final name in memoNames) {
      try {
        await _fetchAndApplyComments(api, name);
      } catch (e) {
        debugPrint('[Sync] _pullCommentsBatch 单篇失败 $name: $e');
      }
    }
  }

  /// 从远端拉取指定日记的评论并逐条合并到本地
  static Future<void> _fetchAndApplyComments(
      MemosApiService api, String memoName) async {
    final remoteComments = await api.listMemoComments(memoName);
    for (final data in remoteComments) {
      final name = data['name'] as String? ?? '';
      if (name.isEmpty) continue;
      await _applyRemoteComment(data, memoName);
    }

    // 删除检测：本地有但远端已不存在的评论，硬删除
    final remoteNames = remoteComments
        .map((d) => d['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
    final localComments =
        await DatabaseService.getCommentsByMemosName(memoName);
    for (final local in localComments) {
      if (local.memosName != null &&
          local.syncStatus == SyncStatus.synced &&
          !remoteNames.contains(local.memosName)) {
        await DatabaseService.hardDeleteComment(local.id);
        debugPrint('[Sync] 评论远端已删除，本地硬删除 id=${local.id}');
      }
    }
  }

  /// 获取所有有远端 name 且状态为 synced 的本地条目（用于全量同步的删除检测）
  static Future<List<MemoEntry>> _getAllSyncedWithMemosName() async {
    final all = await DatabaseService.getAllSyncedMemos();
    return all.where((m) => m.memosName != null).toList();
  }

  // ── 远端附件下载到本地 ────────────────────────────────────────

  /// 将 memo 中所有还没有本地文件的附件下载到本地，并更新 DB
  ///
  /// 后台异步执行，不阻塞同步主流程。单个下载失败不影响其他附件。
  static Future<void> _downloadAttachments(MemoEntry memo, String baseUrl) async {
    final attachments = memo.attachments;
    if (attachments.isEmpty) return;

    final token = await SettingsService.accessToken;
    if (token == null || token.isEmpty) return;

    bool changed = false;
    final updated = <AttachmentInfo>[];
    for (final att in attachments) {
      final newAtt = await AttachmentService.downloadToLocal(att, baseUrl, token);
      updated.add(newAtt);
      if (newAtt.localPath != att.localPath) changed = true;
    }

    if (changed) {
      memo.attachments = updated;
      await DatabaseService.saveMemo(memo, skipTimestamp: true);
      debugPrint('[Sync] 附件下载完成，已更新 memo id=${memo.id}');
    }
  }

  // ── 离线附件补传 ──────────────────────────────────────────────

  /// 将 memo 中尚未上传的附件批量上传，并替换 content 中的本地路径为远端 URL
  ///
  /// 失败的附件标记 uploadFailed=true，不中断整体同步流程。
  static Future<void> _uploadPendingAttachments(
    MemosApiService api,
    MemoEntry memo,
    String baseUrl,
    String token,
  ) async {
    final attachments = memo.attachments;
    if (attachments.isEmpty) return;

    bool changed = false;
    final updated = <AttachmentInfo>[];

    for (final att in attachments) {
      if (att.remoteUrl != null || att.localPath == null) {
        // 已上传或无本地文件，无需处理
        updated.add(att);
        continue;
      }
      debugPrint('[Sync] 补传离线附件 ${att.filename}');
      final newAtt = await AttachmentService.uploadPendingAttachment(
          att, baseUrl, token);
      updated.add(newAtt);

      // 上传成功：将 content 中的 file://本地路径 替换为 remoteUrl
      if (newAtt.remoteUrl != null && att.localPath != null) {
        final localUri = 'file://${att.localPath}';
        memo.content = memo.content.replaceAll(localUri, newAtt.remoteUrl!);
        changed = true;
        debugPrint('[Sync] content 中路径已替换：$localUri → ${newAtt.remoteUrl}');
      }
    }

    if (changed || updated.any((a) => a != attachments[updated.indexOf(a)])) {
      memo.attachments = updated;
      await DatabaseService.saveMemo(memo, skipTimestamp: true);
    }
  }

  // ── 数据转换 ─────────────────────────────────────────────────

  /// 根据远端数据构建一个新的本地 [MemoEntry]
  ///
  /// 解析 createTime / updateTime 字段（UTC → 本地时区）。
  static MemoEntry _buildFromRemote(Map<String, dynamic> data, String baseUrl) {
    final memo = MemoEntry()
      ..memosName = data['name'] as String?
      ..content = data['content'] as String? ?? ''
      ..isPinned = data['pinned'] as bool? ?? false
      ..syncStatus = SyncStatus.synced
      ..lastSyncAt = DateTime.now();

    final ct = data['createTime'] as String?;
    if (ct != null) memo.createdAt = DateTime.parse(ct).toLocal();

    final ut = data['updateTime'] as String?;
    if (ut != null) memo.updatedAt = DateTime.parse(ut).toLocal();

    _applyLocation(memo, data);
    memo.attachments = _parseAttachments(data, baseUrl);

    return memo;
  }

  /// 将远端数据应用到已有本地 [MemoEntry]（覆盖内容和时间戳）
  static void _applyRemoteData(
      MemoEntry memo, Map<String, dynamic> data, String baseUrl) {
    memo.content = data['content'] as String? ?? '';
    memo.isPinned = data['pinned'] as bool? ?? false;

    final ct = data['createTime'] as String?;
    if (ct != null) memo.createdAt = DateTime.parse(ct).toLocal();
    final ut = data['updateTime'] as String?;
    if (ut != null) memo.updatedAt = DateTime.parse(ut).toLocal();

    _applyLocation(memo, data);

    // 合并附件：保留本地已下载的 localPath
    final oldByResName = {
      for (final a in memo.attachments)
        if (a.remoteResName != null) a.remoteResName!: a
    };
    final newAttachments = _parseAttachments(data, baseUrl).map((a) {
      final old = a.remoteResName != null ? oldByResName[a.remoteResName] : null;
      return (old?.localPath != null) ? a.copyWith(localPath: old!.localPath) : a;
    }).toList();

    memo
      ..syncStatus = SyncStatus.synced
      ..lastSyncAt = DateTime.now()
      ..attachments = newAttachments;
  }

  /// 从远端数据中解析 location 字段并写入 memo
  ///
  /// 只有远端有实质性坐标（lat/lng 均非零）时才覆盖本地数据，
  /// 避免远端返回空 location 对象时把本地位置清掉。
  static void _applyLocation(MemoEntry memo, Map<String, dynamic> data) {
    if (!data.containsKey('location') || data['location'] == null) return;
    final loc = data['location'];
    if (loc is! Map) return;
    final lat = (loc['latitude'] as num?)?.toDouble();
    final lng = (loc['longitude'] as num?)?.toDouble();
    // 坐标为 0 或缺失视为无效，保留本地数据
    if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) return;
    final placeholder = loc['placeholder'] as String?;
    memo.location = (placeholder != null && placeholder.isNotEmpty) ? placeholder : null;
    memo.latitude = lat;
    memo.longitude = lng;
  }

  /// 从远端 memo 数据中解析 attachments 列表
  ///
  /// [baseUrl]：服务器地址，用于拼接 /file/{resName}/{filename} 访问 URL
  static List<AttachmentInfo> _parseAttachments(
      Map<String, dynamic> data, String baseUrl) {
    final raw = data['attachments'];
    if (raw == null || raw is! List || raw.isEmpty) return [];

    final result = <AttachmentInfo>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final a = Map<String, dynamic>.from(item);
      final resName = a['name'] as String? ?? '';
      final filename = a['filename'] as String? ?? '';
      final mime = a['type'] as String? ?? 'application/octet-stream';
      final size = int.tryParse(a['size']?.toString() ?? '0') ?? 0;
      final externalLink = a['externalLink'] as String? ?? '';

      if (resName.isEmpty) continue;

      final remotePath = externalLink.isNotEmpty
          ? externalLink
          : '/file/$resName/${Uri.encodeComponent(filename)}';

      result.add(AttachmentInfo(
        localId: resName, // 用 resName 作为稳定 localId
        remoteResName: resName,
        remoteUrl: remotePath,
        filename: filename,
        mimeType: mime,
        sizeBytes: size,
      ));
    }
    debugPrint('[Sync] 解析附件 ${result.length} 个');
    return result;
  }
}
