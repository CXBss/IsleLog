import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/database/database_service.dart';
import '../../data/models/article_entry.dart';
import '../../data/models/attachment_info.dart';
import '../../data/models/comment_entry.dart';
import '../../data/models/folder_entry.dart';
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
  /// [full]：true = 全量拉取 + 删除检测；false = 基于 changelog 增量拉取
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
      // 先 pull：检测冲突，将远端更新拉到本地
      final (pulled, deleted, memosWithComments) =
          await _pullUpdates(api, url, full: full);
      if (memosWithComments.isNotEmpty) {
        await _pullCommentsBatch(api, memosWithComments);
      }
      // 拉取文件夹和文章（先文件夹，再文章）
      await _pullFolders(api);
      await _pullArticles(api);
      // 再 push：冲突条目已被标记为 conflict（不是 pending），不会被推送
      final pushed = await _pushPending(api, url, token);
      await SettingsService.setLastSyncTime(DateTime.now());

      // 全量同步完成后，获取最新 changelogId 作为下次增量同步游标
      if (full) {
        await _saveLatestChangelogId(api);
        // 全量同步完成后重建待办索引（Pull 的数据通过 skipTimestamp 写入，绕过了 saveMemo 的自动更新）
        await DatabaseService.rebuildTodoStatus();
      }

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

  /// 全量同步后调用，将服务端最新 changelogId 保存为增量游标
  static Future<void> _saveLatestChangelogId(MemosApiService api) async {
    try {
      final latest = await api.getLatestChangelog();
      final id = latest != null ? (latest['id'] as int?) ?? -1 : -1;
      await SettingsService.setLastChangelogId(id);
      debugPrint('[Sync] 已保存 changelogId 游标: $id');
    } catch (e) {
      debugPrint('[Sync] 获取最新 changelogId 失败（忽略）: $e');
    }
  }

  /// 直接推送单条 memo 到远端，不经过 pull（用于冲突解决后的推送）
  ///
  /// 抛出异常由调用方处理，不静默失败。
  static Future<void> pushSingleMemo(MemoEntry memo) async {
    debugPrint('[Sync] pushSingleMemo 开始 id=${memo.id} memosName=${memo.memosName}');
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      throw Exception('未配置服务器');
    }
    final api = MemosApiService(baseUrl: url, token: token);
    await _uploadPendingAttachments(api, memo, url, token);
    final attachmentNames = memo.attachments
        .where((a) => a.remoteResName != null)
        .map((a) => a.remoteResName!)
        .toList();

    if (memo.memosName == null) {
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
    } else {
      await api.updateMemo(
        name: memo.memosName!,
        content: memo.content,
        attachmentNames: attachmentNames,
        createTime: memo.createdAt,
        locationPlaceholder: memo.location,
        latitude: memo.latitude,
        longitude: memo.longitude,
      );
      if (memo.isPinned) {
        await api.pinMemo(memo.memosName!);
      } else {
        await api.unpinMemo(memo.memosName!);
      }
      memo
        ..syncStatus = SyncStatus.synced
        ..lastSyncAt = DateTime.now();
    }
    await DatabaseService.saveMemo(memo, skipTimestamp: true);
    debugPrint('[Sync] pushSingleMemo 成功 memosName=${memo.memosName}');
  }

  /// 直接推送单篇文章到远端，不经过 pull（用于冲突解决后的推送）
  ///
  /// 抛出异常由调用方处理，不静默失败。
  static Future<void> pushSingleArticle(ArticleEntry article) async {
    debugPrint('[Sync] pushSingleArticle 开始 id=${article.id} articleName=${article.articleName}');
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      throw Exception('未配置服务器');
    }
    final api = MemosApiService(baseUrl: url, token: token);

    // 解析 folderName（如有本地关联文件夹）
    if (article.folderName == null && article.localFolderId != null) {
      final isar = await DatabaseService.db;
      final folder = await isar.folderEntrys.get(article.localFolderId!);
      if (folder?.folderName != null) {
        article.folderName = folder!.folderName;
      }
    }

    if (article.articleName == null) {
      final data = await api.createArticle(
        title: article.title,
        content: article.content,
        visibility: article.visibility,
        parent: article.folderName,
      );
      article
        ..articleName = data['name'] as String?
        ..syncStatus = SyncStatus.synced
        ..lastSyncAt = DateTime.now();
    } else {
      await api.updateArticle(
        name: article.articleName!,
        title: article.title,
        content: article.content,
        visibility: article.visibility,
        pinned: article.isPinned,
        parent: article.folderName,
        updateParent: true,
      );
      article
        ..syncStatus = SyncStatus.synced
        ..lastSyncAt = DateTime.now();
    }
    await DatabaseService.saveArticle(article, skipTimestamp: true);
    debugPrint('[Sync] pushSingleArticle 成功 articleName=${article.articleName}');
  }

  /// 保存日记后的后台静默同步（先增量 pull 再 push）
  ///
  /// 先 pull 检测冲突，再 push 本地改动。
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
      final (_, __, memosWithComments) = await _pullUpdates(api, url, full: false);
      if (memosWithComments.isNotEmpty) {
        await _pullCommentsBatch(api, memosWithComments);
      }
      final count = await _pushPending(api, url, token);
      await SettingsService.setLastSyncTime(DateTime.now());
      debugPrint('[Sync] pushPendingBackground 完成，推送 $count 条');
    } catch (e) {
      // 静默失败，保持 pending 状态，等待下次手动同步
      debugPrint('[Sync] pushPendingBackground 静默失败：$e');
    }
  }

  /// 编辑保存后的后台冲突检查 + 推送
  ///
  /// 相比 [pushPendingBackground]，优先针对刚保存的 memo 做精准冲突检测：
  /// 拿到 changelog 后先判断当前 memo 是否冲突，再用同一批 changelog 数据
  /// 处理其他条目，避免二次请求。
  ///
  /// 流程：
  /// 1. 新建日记（无 memosName）→ 无需检查，直接走完整 pull+push
  /// 2. 已同步日记 → 获取 changelog：
  ///    a. 当前 memo 有远端变更 → 拉取远端内容标记 conflict，其余条目正常 pull+push
  ///    b. 无变更 → 用同批 changelog 处理所有条目，再 push
  ///    c. changelog 请求失败 → 降级为完整 pull+push
  ///
  /// 静默失败：遇到任何错误只打印日志，不抛出异常。
  static Future<void> checkConflictAndPush(MemoEntry memo) async {
    debugPrint('[Sync] checkConflictAndPush 开始 id=${memo.id} memosName=${memo.memosName}');
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      debugPrint('[Sync] checkConflictAndPush 终止：未配置服务器');
      return;
    }

    final api = MemosApiService(baseUrl: url, token: token);
    try {
      // 新建日记：无远端 ID，直接走完整 pull+push（拉取可能与新内容相关的变更）
      if (memo.memosName == null) {
        debugPrint('[Sync] 新建日记，走完整 pull+push');
        final (_, __, memosWithComments) = await _pullUpdates(api, url, full: false);
        if (memosWithComments.isNotEmpty) await _pullCommentsBatch(api, memosWithComments);
        await _pushPending(api, url, token);
        await SettingsService.setLastSyncTime(DateTime.now());
        return;
      }

      // 已同步日记：先拿 changelog
      final sinceId = await SettingsService.lastChangelogId;
      debugPrint('[Sync] 查 changelog sinceId=$sinceId');

      List<Map<String, dynamic>> changelogs;
      try {
        changelogs = await api.listChangelogs(sinceId);
      } catch (e) {
        // changelog 请求失败 → 降级完整 pull+push
        debugPrint('[Sync] listChangelogs 失败，降级完整 pull+push：$e');
        final (_, __, memosWithComments) = await _pullUpdates(api, url, full: false);
        if (memosWithComments.isNotEmpty) await _pullCommentsBatch(api, memosWithComments);
        await _pushPending(api, url, token);
        await SettingsService.setLastSyncTime(DateTime.now());
        return;
      }

      debugPrint('[Sync] changelog 数量: ${changelogs.length}');

      // 检查当前 memo 是否有远端变更
      final memoIdPart = memo.memosName!.split('/').last;
      final hasRemoteChange = changelogs.any((log) {
        final entity = log['entity'] as String? ?? '';
        final entityId = log['entityId'] as String? ?? '';
        final action = log['action'] as String? ?? '';
        // entityId 可能是完整 memosName 或只有数字 ID 部分
        return entity == 'memo' &&
            (entityId == memo.memosName || entityId == memoIdPart) &&
            action != 'DELETE';
      });

      if (hasRemoteChange) {
        // 当前 memo 有远端变更 → 精准拉取并标记 conflict
        debugPrint('[Sync] 发现远端变更，拉取内容并标记 conflict: ${memo.memosName}');
        try {
          final remoteData = await api.getMemo(memoIdPart);
          final remoteContent = remoteData['content'] as String? ?? '';
          final latestMemo = await DatabaseService.getMemoById(memo.id);
          if (latestMemo != null) {
            latestMemo
              ..syncStatus = SyncStatus.conflict
              ..conflictRemoteContent = remoteContent;
            await DatabaseService.saveMemo(latestMemo, skipTimestamp: true);
            debugPrint('[Sync] 已标记 conflict id=${memo.id}');
          }
        } catch (e) {
          debugPrint('[Sync] 拉取远端内容失败，保持 pending：$e');
        }
      }

      // 无论当前 memo 是否冲突，都用同批 changelog 处理其余条目 + 推送
      // （当前 memo 若已标记 conflict，_pushPending 会自动跳过它）
      await _applyChangelogData(api, url, changelogs);
      await _pushPending(api, url, token);
      await SettingsService.setLastSyncTime(DateTime.now());

      // 更新 changelog 游标
      if (changelogs.isNotEmpty) {
        final newId = changelogs.last['id'] as int;
        await SettingsService.setLastChangelogId(newId);
        debugPrint('[Sync] 更新 changelogId 游标: $newId');
      }
    } catch (e) {
      debugPrint('[Sync] checkConflictAndPush 静默失败：$e');
    }
  }

  /// 将已获取的 changelog 列表应用到本地（供 [checkConflictAndPush] 复用，避免二次请求）
  ///
  /// 逻辑与 [_pullByChangelog] 的核心处理部分相同，但跳过 changelog 请求和游标更新。
  static Future<void> _applyChangelogData(
      MemosApiService api, String baseUrl, List<Map<String, dynamic>> changelogs) async {
    final memoNames = <String>{};
    final deletedNames = <String>{};

    for (final log in changelogs) {
      final entity = log['entity'] as String? ?? '';
      final entityId = log['entityId'] as String? ?? '';
      final action = log['action'] as String? ?? '';
      if (entity != 'memo' || entityId.isEmpty) continue;
      if (action == 'DELETE') {
        deletedNames.add(entityId);
      } else {
        memoNames.add(entityId);
      }
    }
    memoNames.removeAll(deletedNames);

    debugPrint('[Sync] _applyChangelogData: 更新/新增 ${memoNames.length} 条，删除 ${deletedNames.length} 条');

    final memosWithComments = <String>{};
    for (final name in memoNames) {
      try {
        final idPart = name.split('/').last;
        final data = await api.getMemo(idPart);
        final state = data['state'] as String? ?? 'NORMAL';
        await _applyRemoteMemo(data, baseUrl, archived: state == 'ARCHIVED');
        _collectCommentRefs(data, memosWithComments);
      } catch (e) {
        debugPrint('[Sync] _applyChangelogData 拉取 $name 失败：$e');
      }
    }

    for (final name in deletedNames) {
      final local = await DatabaseService.getMemoByMemosName(name);
      if (local != null && local.syncStatus == SyncStatus.synced) {
        await DatabaseService.hardDelete(local.id);
        debugPrint('[Sync] changelog 删除本地 memo $name');
      }
    }

    if (memosWithComments.isNotEmpty) {
      await _pullCommentsBatch(api, memosWithComments);
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
    // ── 推送文件夹（先于文章，确保 folderName 有值）──
    count += await _pushPendingFolders(api);
    // ── 推送文章 ──
    count += await _pushPendingArticles(api);
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
  /// [full]：true = 全量拉取 + 远端删除检测；
  ///         false = 基于 changelog 增量拉取，若变更数超阈值则自动降级全量。
  /// 返回 (合并条目数, 删除条目数, 有评论的日记 memosName 集合)。
  static Future<(int, int, Set<String>)> _pullUpdates(
      MemosApiService api, String baseUrl,
      {bool full = false}) async {
    if (!full) {
      return _pullByChangelog(api, baseUrl);
    }
    return _pullFull(api, baseUrl);
  }

  /// 全量拉取：拉取所有条目 + 删除检测
  static Future<(int, int, Set<String>)> _pullFull(
      MemosApiService api, String baseUrl) async {
    debugPrint('[Sync] _pullFull 全量拉取开始');
    final normalMemos = await api.listAllMemos(state: 'NORMAL');
    final archivedMemos = await api.listAllMemos(state: 'ARCHIVED');
    debugPrint('[Sync] 远端 NORMAL=${normalMemos.length} ARCHIVED=${archivedMemos.length}');

    final remoteNames = <String>{};
    final memosWithComments = <String>{};
    int pulled = 0;

    Future<void> processList(List<Map<String, dynamic>> list, bool archived) async {
      for (final data in list) {
        final remoteName = data['name'] as String? ?? '';
        if (remoteName.isEmpty) continue;
        remoteNames.add(remoteName);
        pulled += await _applyRemoteMemo(data, baseUrl, archived: archived);
        _collectCommentRefs(data, memosWithComments);
      }
    }

    await processList(normalMemos, false);
    await processList(archivedMemos, true);

    // 删除检测
    int deleted = 0;
    final allLocal = await _getAllSyncedWithMemosName();
    for (final local in allLocal) {
      if (!remoteNames.contains(local.memosName)) {
        debugPrint('[Sync] 远端已删除，本地同步删除 id=${local.id} memosName=${local.memosName}');
        await DatabaseService.hardDelete(local.id);
        deleted++;
      }
    }

    debugPrint('[Sync] _pullFull 完成，拉取 $pulled 条，删除 $deleted 条');
    return (pulled, deleted, memosWithComments);
  }

  /// 增量拉取：通过 changelog 驱动，超阈值时降级为全量
  ///
  /// 动态阈值 = max(300, 本地总日记数 × 0.3)，
  /// 避免小库用户阈值过低、大库用户阈值固定不足的问题。
  static Future<(int, int, Set<String>)> _pullByChangelog(
      MemosApiService api, String baseUrl) async {
    final sinceId = await SettingsService.lastChangelogId;

    // 首次同步（无游标）→ 直接全量
    if (sinceId == -1) {
      debugPrint('[Sync] _pullByChangelog 无游标，降级全量');
      return _pullFull(api, baseUrl);
    }

    debugPrint('[Sync] _pullByChangelog 增量，sinceId=$sinceId');
    final List<Map<String, dynamic>> changelogs;
    try {
      changelogs = await api.listChangelogs(sinceId);
    } catch (e) {
      debugPrint('[Sync] listChangelogs 失败，降级全量：$e');
      return _pullFull(api, baseUrl);
    }

    debugPrint('[Sync] changelog 数量: ${changelogs.length}');

    // 动态阈值：max(300, 本地总数 × 30%)
    final localTotal = await DatabaseService.getMemoCount();
    final threshold = (localTotal * 0.3).ceil().clamp(300, 999999);
    debugPrint('[Sync] 降级阈值: $threshold（本地总数 $localTotal）');

    if (changelogs.length >= threshold) {
      debugPrint('[Sync] changelog 超过阈值 $threshold，降级全量同步');
      return _pullFull(api, baseUrl);
    }

    // 按 entity 分类处理
    final memoNames = <String>{};      // 需要拉取最新数据的 memo
    final deletedNames = <String>{};   // 需要本地删除的 memo

    for (final log in changelogs) {
      final entity = log['entity'] as String? ?? '';
      final entityId = log['entityId'] as String? ?? '';
      final action = log['action'] as String? ?? '';
      if (entity != 'memo' || entityId.isEmpty) continue;
      if (action == 'DELETE') {
        deletedNames.add(entityId);
      } else {
        memoNames.add(entityId);
      }
    }
    // 已删除的不再拉取
    memoNames.removeAll(deletedNames);

    debugPrint('[Sync] changelog 涉及 memo: 更新/新增 ${memoNames.length} 条，删除 ${deletedNames.length} 条');

    int pulled = 0;
    int deleted = 0;
    final memosWithComments = <String>{};

    // 拉取有变化的 memo 详情
    for (final name in memoNames) {
      try {
        final idPart = name.split('/').last;
        final data = await api.getMemo(idPart);
        final state = data['state'] as String? ?? 'NORMAL';
        pulled += await _applyRemoteMemo(data, baseUrl, archived: state == 'ARCHIVED');
        _collectCommentRefs(data, memosWithComments);
      } catch (e) {
        debugPrint('[Sync] 拉取 memo $name 详情失败：$e');
      }
    }

    // 处理远端删除
    for (final name in deletedNames) {
      final local = await DatabaseService.getMemoByMemosName(name);
      if (local != null && local.syncStatus == SyncStatus.synced) {
        await DatabaseService.hardDelete(local.id);
        deleted++;
        debugPrint('[Sync] changelog 删除本地 memo $name');
      }
    }

    // 更新 changelog 游标为本批最后一条 id
    if (changelogs.isNotEmpty) {
      final newId = changelogs.last['id'] as int;
      await SettingsService.setLastChangelogId(newId);
      debugPrint('[Sync] 更新 changelogId 游标: $newId');
    }

    debugPrint('[Sync] _pullByChangelog 完成，拉取 $pulled 条，删除 $deleted 条');
    return (pulled, deleted, memosWithComments);
  }

  /// 从 memo 数据中提取有评论引用的日记名（relations[type=COMMENT]）
  static void _collectCommentRefs(
      Map<String, dynamic> data, Set<String> memosWithComments) {
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
      // 本地有未推送修改，远端也有新版本 → 冲突
      // 保留本地 content 不变，将远端内容存入 conflictRemoteContent
      final remoteContent = data['content'] as String? ?? '';
      debugPrint('[Sync] 检测到冲突，标记 conflict: $remoteName');
      localMemo
        ..syncStatus = SyncStatus.conflict
        ..conflictRemoteContent = remoteContent;
      await DatabaseService.saveMemo(localMemo, skipTimestamp: true);
    } else if (localMemo.syncStatus == SyncStatus.conflict) {
      // 已是冲突状态，远端又有新版本 → 只更新远端版本内容，不覆盖本地
      final remoteContent = data['content'] as String? ?? '';
      debugPrint('[Sync] 冲突状态下远端再次更新，更新 conflictRemoteContent: $remoteName');
      localMemo.conflictRemoteContent = remoteContent;
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

  // ────────────────────────────────────────────────────────────────
  // 文件夹同步
  // ────────────────────────────────────────────────────────────────

  /// 推送所有 pending 文件夹到远端
  ///
  /// 先推文件夹，再推文章，保证文章 push 时 folderName 已有值。
  static Future<int> _pushPendingFolders(MemosApiService api) async {
    final pending = await DatabaseService.getPendingSyncFolders();
    debugPrint('[Sync] _pushPendingFolders: ${pending.length} 个待推送');
    int count = 0;
    for (final folder in pending) {
      try {
        if (folder.isDeleted) {
          if (folder.folderName != null) {
            await api.deleteFolder(folder.folderName!);
          }
          await DatabaseService.hardDeleteFolder(folder.id);
        } else if (folder.folderName == null) {
          // 新建文件夹
          // 若有离线父文件夹，先尝试解析 parentFolderName
          String? parentFolderName = folder.parentFolderName;
          if (parentFolderName == null && folder.localParentFolderId != null) {
            // 父文件夹可能还没同步，尝试从本地获取 folderName
            final parentEntry = await (await DatabaseService.db)
                .folderEntrys.get(folder.localParentFolderId!);
            if (parentEntry != null && parentEntry.folderName != null) {
              parentFolderName = parentEntry.folderName;
            }
          }
          final data = await api.createFolder(
            title: folder.title,
            parent: parentFolderName,
          );
          folder
            ..folderName = data['name'] as String?
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveFolder(folder, skipTimestamp: true);
          // 更新依赖此 localFolderId 的文章/子文件夹
          await _resolveLocalFolderRefs(folder);
        } else {
          // 更新文件夹
          await api.updateFolder(
            name: folder.folderName!,
            title: folder.title,
            parent: folder.parentFolderName,
          );
          folder
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveFolder(folder, skipTimestamp: true);
        }
        count++;
      } catch (e) {
        debugPrint('[Sync] 文件夹推送失败 id=${folder.id}: $e（保持 pending）');
      }
    }
    debugPrint('[Sync] _pushPendingFolders 完成，推送 $count 个');
    return count;
  }

  /// 文件夹同步成功后，将引用其 localId 的文章/子文件夹更新为 folderName
  static Future<void> _resolveLocalFolderRefs(FolderEntry folder) async {
    if (folder.folderName == null) return;
    await DatabaseService.resolveLocalFolderRefs(folder.id, folder.folderName!);
  }

  /// 从远端拉取文件夹列表，合并到本地
  static Future<int> _pullFolders(MemosApiService api) async {
    debugPrint('[Sync] _pullFolders 开始');
    int pulled = 0;
    try {
      final remoteFolders = await api.listFolders();
      final remoteNames = remoteFolders.map((f) => f['name'] as String).toSet();

      for (final data in remoteFolders) {
        final name = data['name'] as String;
        final local = await DatabaseService.getFolderByFolderName(name);
        if (local == null) {
          // 远端有，本地无 → 新增
          final folder = FolderEntry()
            ..folderName = name
            ..title = data['title'] as String? ?? ''
            ..parentFolderName = data['parent'] as String?
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveFolder(folder, skipTimestamp: true);
          pulled++;
        } else if (local.syncStatus == SyncStatus.synced) {
          // 本地已同步 → 覆盖为远端最新
          local
            ..title = data['title'] as String? ?? ''
            ..parentFolderName = data['parent'] as String?
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveFolder(local, skipTimestamp: true);
          pulled++;
        }
        // 本地 pending → 保持本地版本，不覆盖
      }

      // 检测远端已删除的文件夹（本地 synced 但远端不存在）
      final localSynced = await DatabaseService.getAllSyncedFolders();
      for (final local in localSynced) {
        if (local.folderName != null && !remoteNames.contains(local.folderName)) {
          await DatabaseService.hardDeleteFolder(local.id);
          debugPrint('[Sync] 文件夹远端已删除，本地物理删除 folderName=${local.folderName}');
        }
      }
    } catch (e) {
      debugPrint('[Sync] _pullFolders 失败: $e');
    }
    debugPrint('[Sync] _pullFolders 完成，拉取 $pulled 个');
    return pulled;
  }

  // ────────────────────────────────────────────────────────────────
  // 文章同步
  // ────────────────────────────────────────────────────────────────

  /// 推送所有 pending 文章到远端
  static Future<int> _pushPendingArticles(MemosApiService api) async {
    final pending = await DatabaseService.getPendingSyncArticles();
    debugPrint('[Sync] _pushPendingArticles: ${pending.length} 篇待推送');
    int count = 0;
    for (final article in pending) {
      try {
        // 如果 folderName 还空但有 localFolderId，尝试从本地获取
        if (article.folderName == null && article.localFolderId != null) {
          final isar = await DatabaseService.db;
          final folder = await isar.folderEntrys.get(article.localFolderId!);
          if (folder != null && folder.folderName != null) {
            article.folderName = folder.folderName;
          } else {
            // 父文件夹还未同步，跳过本文章，等下次
            debugPrint('[Sync] 文章 id=${article.id} 的文件夹尚未同步，跳过');
            continue;
          }
        }

        if (article.isDeleted) {
          if (article.articleName != null) {
            await api.deleteArticle(article.articleName!);
          }
          await DatabaseService.hardDeleteArticle(article.id);
        } else if (article.articleName == null) {
          // 新建：folderName 为 null 且 localFolderId 也为 null → 放根目录，不传 parent
          final data = await api.createArticle(
            title: article.title,
            content: article.content,
            visibility: article.visibility,
            parent: article.folderName, // null 时服务端放根目录
          );
          article
            ..articleName = data['name'] as String?
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveArticle(article, skipTimestamp: true);
        } else {
          // 更新：始终传 parent，让服务端能正确写入或清空 parent_id
          await api.updateArticle(
            name: article.articleName!,
            title: article.title,
            content: article.content,
            visibility: article.visibility,
            pinned: article.isPinned,
            parent: article.folderName, // null = 根目录
            updateParent: true,
          );
          article
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveArticle(article, skipTimestamp: true);
        }
        count++;
      } catch (e) {
        debugPrint('[Sync] 文章推送失败 id=${article.id}: $e（保持 pending）');
      }
    }
    debugPrint('[Sync] _pushPendingArticles 完成，推送 $count 篇');
    return count;
  }

  /// 从远端拉取文章列表，合并到本地
  static Future<int> _pullArticles(MemosApiService api) async {
    debugPrint('[Sync] _pullArticles 开始');
    int pulled = 0;
    try {
      final remoteArticles = await api.listAllArticles();
      final remoteNames = remoteArticles.map((a) => a['name'] as String).toSet();

      for (final data in remoteArticles) {
        final name = data['name'] as String;
        final local = await DatabaseService.getArticleByArticleName(name);
        if (local == null) {
          final article = _articleFromRemote(data);
          await DatabaseService.saveArticle(article, skipTimestamp: true);
          pulled++;
        } else if (local.syncStatus == SyncStatus.synced) {
          _applyRemoteArticle(local, data);
          await DatabaseService.saveArticle(local, skipTimestamp: true);
          pulled++;
        } else if (local.syncStatus == SyncStatus.pending) {
          // 双方都改了 → 标记 conflict
          local
            ..conflictRemoteContent = data['content'] as String?
            ..conflictRemoteTitle = data['title'] as String?
            ..syncStatus = SyncStatus.conflict;
          await DatabaseService.saveArticle(local, skipTimestamp: true);
          debugPrint('[Sync] 文章冲突 articleName=$name');
        }
      }

      // 检测远端已删除的文章
      final localSynced = await DatabaseService.getAllSyncedArticles();
      for (final local in localSynced) {
        if (local.articleName != null && !remoteNames.contains(local.articleName)) {
          await DatabaseService.hardDeleteArticle(local.id);
          debugPrint('[Sync] 文章远端已删除，本地物理删除 articleName=${local.articleName}');
        }
      }
    } catch (e) {
      debugPrint('[Sync] _pullArticles 失败: $e');
    }
    debugPrint('[Sync] _pullArticles 完成，拉取 $pulled 篇');
    return pulled;
  }

  static ArticleEntry _articleFromRemote(Map<String, dynamic> data) {
    final article = ArticleEntry()
      ..articleName = data['name'] as String?
      ..title = data['title'] as String? ?? ''
      ..content = data['content'] as String? ?? ''
      ..folderName = data['parent'] as String?
      ..visibility = data['visibility'] as String? ?? 'PRIVATE'
      ..isPinned = data['pinned'] as bool? ?? false
      ..isArchived = (data['state'] as String?) == 'ARCHIVED'
      ..syncStatus = SyncStatus.synced
      ..lastSyncAt = DateTime.now();
    final createTime = data['createTime'] as String?;
    if (createTime != null) {
      article.createdAt = DateTime.parse(createTime).toLocal();
    }
    final updateTime = data['updateTime'] as String?;
    if (updateTime != null) {
      article.updatedAt = DateTime.parse(updateTime).toLocal();
    }
    return article;
  }

  static void _applyRemoteArticle(ArticleEntry article, Map<String, dynamic> data) {
    article
      ..title = data['title'] as String? ?? ''
      ..content = data['content'] as String? ?? ''
      ..folderName = data['parent'] as String?
      ..localFolderId = null // 同步后以远端 folderName 为准，清除离线关联
      ..visibility = data['visibility'] as String? ?? 'PRIVATE'
      ..isPinned = data['pinned'] as bool? ?? false
      ..isArchived = (data['state'] as String?) == 'ARCHIVED'
      ..syncStatus = SyncStatus.synced
      ..lastSyncAt = DateTime.now();
    final updateTime = data['updateTime'] as String?;
    if (updateTime != null) {
      article.updatedAt = DateTime.parse(updateTime).toLocal();
    }
  }
}
