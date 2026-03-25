import 'package:flutter/foundation.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../shared/constants/app_constants.dart';
import '../api/memos_api_service.dart';
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
      final pushed = await _pushPending(api);
      final pulled = await _pullUpdates(api);
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
      final count = await _pushPending(api);
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
  static Future<int> _pushPending(MemosApiService api) async {
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
        } else if (memo.memosName == null) {
          // ── 处理新建：推送到远端，将返回的资源名写回本地 ──
          debugPrint('[Sync] 新建远端 memo id=${memo.id}');
          final remoteData = await api.createMemo(content: memo.content);
          memo
            ..memosName = remoteData['name'] as String?
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveMemo(memo, skipTimestamp: true);
          debugPrint('[Sync] 新建成功，memosName=${memo.memosName}');
        } else {
          // ── 处理更新：用本地内容覆盖远端 ──
          debugPrint('[Sync] 更新远端 memo: ${memo.memosName}');
          await api.updateMemo(name: memo.memosName!, content: memo.content);
          memo
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveMemo(memo, skipTimestamp: true);
          debugPrint('[Sync] 更新成功，memosName=${memo.memosName}');
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
  static Future<int> _pullUpdates(MemosApiService api) async {
    // 尝试增量同步：只拉取自上次同步后有变动的 memo
    final lastSync = await SettingsService.lastSyncTime;
    String? filter;
    if (lastSync != null) {
      final timeStr = lastSync.toUtc().toIso8601String();
      filter = 'updateTime >= "$timeStr"';
      debugPrint('[Sync] _pullUpdates 增量拉取，filter=$filter');
    } else {
      debugPrint('[Sync] _pullUpdates 首次同步，全量拉取');
    }

    List<Map<String, dynamic>> remoteMemos;
    try {
      remoteMemos = await api.listAllMemos(filter: filter);
    } catch (e) {
      // filter 语法不被当前版本支持时，静默回退全量拉取
      debugPrint('[Sync] filter 不支持，回退全量拉取：$e');
      remoteMemos = await api.listAllMemos();
    }
    debugPrint('[Sync] 远端返回 ${remoteMemos.length} 条数据');

    int count = 0;
    for (final data in remoteMemos) {
      // 只处理正常状态的 memo，跳过已归档/已删除
      final state = data['state'] as String? ?? 'NORMAL';
      if (state != 'NORMAL' && state != 'STATE_UNSPECIFIED') {
        debugPrint('[Sync] 跳过非正常状态 memo: state=$state name=${data["name"]}');
        continue;
      }

      final remoteName = data['name'] as String? ?? '';
      if (remoteName.isEmpty) {
        debugPrint('[Sync] 跳过无 name 的远端 memo');
        continue;
      }

      final localMemo = await DatabaseService.getMemoByMemosName(remoteName);

      if (localMemo == null) {
        // 远端有、本地无 → 新增到本地
        debugPrint('[Sync] 新增本地 memo from remote: $remoteName');
        final newMemo = _buildFromRemote(data);
        await DatabaseService.saveMemo(newMemo, skipTimestamp: true);
        count++;
      } else if (localMemo.syncStatus == SyncStatus.synced) {
        // 本地 synced（未修改） → 直接覆盖为远端最新
        debugPrint('[Sync] 更新本地 memo from remote: $remoteName');
        _applyRemoteData(localMemo, data);
        await DatabaseService.saveMemo(localMemo, skipTimestamp: true);
        count++;
      } else if (localMemo.syncStatus == SyncStatus.pending) {
        // 本地和远端均有修改 → 标记冲突，保留本地版本，由用户手动处理
        debugPrint('[Sync] 检测到冲突，标记 conflict: $remoteName');
        localMemo.syncStatus = SyncStatus.conflict;
        await DatabaseService.saveMemo(localMemo, skipTimestamp: true);
      }
      // SyncStatus.conflict 状态不自动合并，等待用户干预
    }

    debugPrint('[Sync] _pullUpdates 完成，合并 $count 条');
    return count;
  }

  // ── 数据转换 ─────────────────────────────────────────────────

  /// 根据远端数据构建一个新的本地 [MemoEntry]
  ///
  /// 解析 createTime / updateTime 字段（UTC → 本地时区）。
  static MemoEntry _buildFromRemote(Map<String, dynamic> data) {
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

    return memo;
  }

  /// 将远端数据应用到已有本地 [MemoEntry]（覆盖内容和时间戳）
  static void _applyRemoteData(
      MemoEntry memo, Map<String, dynamic> data) {
    memo.content = data['content'] as String? ?? '';

    // 只更新 updateTime，createTime 保持本地原始值
    final ut = data['updateTime'] as String?;
    if (ut != null) memo.updatedAt = DateTime.parse(ut).toLocal();

    memo
      ..syncStatus = SyncStatus.synced
      ..lastSyncAt = DateTime.now();
  }
}
