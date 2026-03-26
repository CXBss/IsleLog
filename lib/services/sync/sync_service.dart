import 'package:flutter/foundation.dart';

import '../../data/database/database_service.dart';
import '../../data/models/attachment_info.dart';
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

  /// 错误信息（null 表示同步成功）
  final String? error;

  const SyncResult({this.pushed = 0, this.pulled = 0, this.error});

  /// true 表示本次同步没有发生错误
  bool get success => error == null;

  @override
  String toString() => success
      ? '同步完成：推送 $pushed 条，拉取 $pulled 条'
      : '同步失败：$error';
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

  /// 执行完整双向同步（先 Push 再 Pull）
  ///
  /// 如未配置服务器，直接返回错误结果而不发起任何网络请求。
  /// 同步成功后自动更新 [SettingsService.lastSyncTime]。
  static Future<SyncResult> syncAll() async {
    debugPrint('[Sync] syncAll 开始');

    // 前置检查：确保服务器已配置
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      debugPrint('[Sync] syncAll 终止：未配置服务器');
      return const SyncResult(error: AppStrings.syncNoConfig);
    }

    final api = MemosApiService(baseUrl: url, token: token);
    try {
      final pushed = await _pushPending(api, url, token);
      final pulled = await _pullUpdates(api, url);
      await SettingsService.setLastSyncTime(DateTime.now());
      final result = SyncResult(pushed: pushed, pulled: pulled);
      debugPrint('[Sync] syncAll 完成：$result');
      return result;
    } on MemosApiException catch (e) {
      debugPrint('[Sync] syncAll API 异常：${e.message}');
      return SyncResult(error: e.message);
    } catch (e) {
      debugPrint('[Sync] syncAll 未知异常：$e');
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
            );
            memo
              ..memosName = remoteData['name'] as String?
              ..syncStatus = SyncStatus.synced
              ..lastSyncAt = DateTime.now();
            await DatabaseService.saveMemo(memo, skipTimestamp: true);
            debugPrint('[Sync] 新建成功，memosName=${memo.memosName}');
          } else {
            // ── 处理更新 ──
            debugPrint('[Sync] 更新远端 memo: ${memo.memosName}，附件 ${attachmentNames.length} 个');
            await api.updateMemo(
              name: memo.memosName!,
              content: memo.content,
              attachmentNames: attachmentNames,
            );
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
    return count;
  }

  // ── Pull（远端 → 本地）──────────────────────────────────────

  /// 从远端拉取更新并合并到本地
  ///
  /// 优先使用增量同步（基于 lastSyncTime 过滤），
  /// 若服务端不支持 filter 则静默降级为全量拉取。
  /// 返回合并到本地的新/更新条目数。
  static Future<int> _pullUpdates(MemosApiService api, String baseUrl) async {
    final lastSync = await SettingsService.lastSyncTime;
    String? filter;
    if (lastSync != null) {
      final timeStr = lastSync.toUtc().toIso8601String();
      filter = 'updateTime >= "$timeStr"';
      debugPrint('[Sync] _pullUpdates 增量拉取，filter=$filter');
    } else {
      debugPrint('[Sync] _pullUpdates 首次同步，全量拉取');
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

    // 建立远端所有 name 的集合，用于检测本地已不存在于远端的条目
    final remoteNames = <String>{};
    int count = 0;

    // 处理 NORMAL memos
    for (final data in normalMemos) {
      final remoteName = data['name'] as String? ?? '';
      if (remoteName.isEmpty) continue;
      remoteNames.add(remoteName);
      count += await _applyRemoteMemo(data, baseUrl, archived: false);
    }

    // 处理 ARCHIVED memos
    for (final data in archivedMemos) {
      final remoteName = data['name'] as String? ?? '';
      if (remoteName.isEmpty) continue;
      remoteNames.add(remoteName);
      count += await _applyRemoteMemo(data, baseUrl, archived: true);
    }

    // 检测远端已删除的条目：本地 synced 且有 memosName，但不在远端列表中 → 本地物理删除
    // 仅在全量同步时执行（增量同步无法判断是否真的删除）
    if (filter == null) {
      final allLocal = await _getAllSyncedWithMemosName();
      for (final local in allLocal) {
        if (!remoteNames.contains(local.memosName)) {
          debugPrint('[Sync] 远端已删除，本地同步删除 id=${local.id} memosName=${local.memosName}');
          await DatabaseService.hardDelete(local.id);
          count++;
        }
      }
    }

    debugPrint('[Sync] _pullUpdates 完成，合并 $count 条');
    return count;
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
      return 1;
    } else if (localMemo.syncStatus == SyncStatus.synced) {
      _applyRemoteData(localMemo, data, baseUrl);
      localMemo.isArchived = archived;
      await DatabaseService.saveMemo(localMemo, skipTimestamp: true);
      debugPrint('[Sync] 更新本地 memo: $remoteName archived=$archived');
      return 1;
    } else if (localMemo.syncStatus == SyncStatus.pending) {
      debugPrint('[Sync] 检测到冲突，标记 conflict: $remoteName');
      localMemo.syncStatus = SyncStatus.conflict;
      await DatabaseService.saveMemo(localMemo, skipTimestamp: true);
    }
    return 0;
  }

  /// 获取所有已同步且有远端 name 的本地条目（用于检测远端删除）
  static Future<List<MemoEntry>> _getAllSyncedWithMemosName() async {
    // 复用 DatabaseService 封装，避免直接操作 Isar QueryBuilder 类型问题
    final pending = await DatabaseService.getPendingSyncMemos(); // pending
    final all = await DatabaseService.getAllSyncedMemos();
    return all.where((m) => m.memosName != null && !pending.any((p) => p.id == m.id)).toList();
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
      ..syncStatus = SyncStatus.synced
      ..lastSyncAt = DateTime.now();

    // 解析创建时间（UTC ISO8601 → 本地时区）
    final ct = data['createTime'] as String?;
    if (ct != null) memo.createdAt = DateTime.parse(ct).toLocal();

    // 解析更新时间
    final ut = data['updateTime'] as String?;
    if (ut != null) memo.updatedAt = DateTime.parse(ut).toLocal();

    memo.attachments = _parseAttachments(data, baseUrl);

    return memo;
  }

  /// 将远端数据应用到已有本地 [MemoEntry]（覆盖内容和时间戳）
  static void _applyRemoteData(
      MemoEntry memo, Map<String, dynamic> data, String baseUrl) {
    memo.content = data['content'] as String? ?? '';

    // 只更新 updateTime，createTime 保持本地原始值
    final ut = data['updateTime'] as String?;
    if (ut != null) memo.updatedAt = DateTime.parse(ut).toLocal();

    memo
      ..syncStatus = SyncStatus.synced
      ..lastSyncAt = DateTime.now()
      ..attachments = _parseAttachments(data, baseUrl);
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

      final remoteUrl = externalLink.isNotEmpty
          ? externalLink
          : '$baseUrl/file/$resName/${Uri.encodeComponent(filename)}';

      result.add(AttachmentInfo(
        localId: resName, // 用 resName 作为稳定 localId
        remoteResName: resName,
        remoteUrl: remoteUrl,
        filename: filename,
        mimeType: mime,
        sizeBytes: size,
      ));
    }
    debugPrint('[Sync] 解析附件 ${result.length} 个');
    return result;
  }
}
