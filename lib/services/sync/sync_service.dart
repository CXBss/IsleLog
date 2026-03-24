import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../api/memos_api_service.dart';
import '../settings/settings_service.dart';

/// 同步结果
class SyncResult {
  final int pushed;
  final int pulled;
  final String? error;

  const SyncResult({this.pushed = 0, this.pulled = 0, this.error});

  bool get success => error == null;

  @override
  String toString() => success
      ? '同步完成：推送 $pushed 条，拉取 $pulled 条'
      : '同步失败：$error';
}

/// 离线优先同步引擎
///
/// 策略：
/// 1. **Push**：将本地 `pending` 条目推送到远端（新建/更新/删除）
/// 2. **Pull**：拉取远端增量更新（以 lastSyncTime 为锚点），合并到本地
/// 3. **冲突处理**：本地 pending + 远端有更新 → 标记 `conflict`，保留本地版本
class SyncService {
  SyncService._();

  // ── 公开接口 ──────────────────────────────────────────────────

  /// 完整双向同步（先 Push 再 Pull）
  static Future<SyncResult> syncAll() async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      return const SyncResult(error: '未配置服务器，请先在设置页填写服务器地址和 Token');
    }

    final api = MemosApiService(baseUrl: url, token: token);
    try {
      final pushed = await _pushPending(api);
      final pulled = await _pullUpdates(api);
      await SettingsService.setLastSyncTime(DateTime.now());
      return SyncResult(pushed: pushed, pulled: pulled);
    } on MemosApiException catch (e) {
      return SyncResult(error: e.message);
    } catch (e) {
      return SyncResult(error: e.toString());
    }
  }

  /// 仅推送本地 pending 条目（保存日记后的后台静默推送）
  static Future<void> pushPendingBackground() async {
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) return;

    final api = MemosApiService(baseUrl: url, token: token);
    try {
      await _pushPending(api);
    } catch (_) {
      // 静默失败，保持 pending 状态，等待下次手动同步
    }
  }

  // ── Push（本地 pending → 远端）───────────────────────────────

  static Future<int> _pushPending(MemosApiService api) async {
    final pendingList = await DatabaseService.getPendingSyncMemos();
    int count = 0;

    for (final memo in pendingList) {
      try {
        if (memo.isDeleted) {
          // 软删除：若已有远端 ID 则删除远端，然后本地物理删除
          if (memo.memosName != null) {
            await api.deleteMemo(memo.memosName!);
          }
          await DatabaseService.hardDelete(memo.id);
        } else if (memo.memosName == null) {
          // 新建：推送到远端，将返回的资源名写回本地
          final remoteData = await api.createMemo(content: memo.content);
          memo
            ..memosName = remoteData['name'] as String?
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveMemo(memo, skipTimestamp: true);
        } else {
          // 已有远端 ID：更新远端内容
          await api.updateMemo(
              name: memo.memosName!, content: memo.content);
          memo
            ..syncStatus = SyncStatus.synced
            ..lastSyncAt = DateTime.now();
          await DatabaseService.saveMemo(memo, skipTimestamp: true);
        }
        count++;
      } catch (_) {
        // 单条失败不中断，保持 pending，等待下次同步
      }
    }
    return count;
  }

  // ── Pull（远端 → 本地）──────────────────────────────────────

  static Future<int> _pullUpdates(MemosApiService api) async {
    // 增量同步：只拉取上次同步后有变动的 memo
    final lastSync = await SettingsService.lastSyncTime;
    String? filter;
    if (lastSync != null) {
      final timeStr = lastSync.toUtc().toIso8601String();
      filter = 'updateTime >= "$timeStr"';
    }

    List<Map<String, dynamic>> remoteMemos;
    try {
      remoteMemos = await api.listAllMemos(filter: filter);
    } catch (_) {
      // filter 语法不被当前版本支持时，回退全量拉取
      remoteMemos = await api.listAllMemos();
    }

    int count = 0;
    for (final data in remoteMemos) {
      // 只处理正常状态的 memo，跳过已归档
      final state = data['state'] as String? ?? 'NORMAL';
      if (state != 'NORMAL' && state != 'STATE_UNSPECIFIED') continue;

      final remoteName = data['name'] as String? ?? '';
      if (remoteName.isEmpty) continue;

      final localMemo =
          await DatabaseService.getMemoByMemosName(remoteName);

      if (localMemo == null) {
        // 远端有、本地无 → 新增到本地
        final newMemo = _buildFromRemote(data);
        await DatabaseService.saveMemo(newMemo, skipTimestamp: true);
        count++;
      } else if (localMemo.syncStatus == SyncStatus.synced) {
        // 本地未修改 → 直接覆盖为远端最新
        _applyRemoteData(localMemo, data);
        await DatabaseService.saveMemo(localMemo, skipTimestamp: true);
        count++;
      } else if (localMemo.syncStatus == SyncStatus.pending) {
        // 本地和远端均有修改 → 标记冲突，保留本地版本待用户处理
        localMemo.syncStatus = SyncStatus.conflict;
        await DatabaseService.saveMemo(localMemo, skipTimestamp: true);
      }
      // conflict 状态不自动合并
    }
    return count;
  }

  // ── 数据转换 ─────────────────────────────────────────────────

  static MemoEntry _buildFromRemote(Map<String, dynamic> data) {
    final memo = MemoEntry()
      ..memosName = data['name'] as String?
      ..content = data['content'] as String? ?? ''
      ..syncStatus = SyncStatus.synced
      ..lastSyncAt = DateTime.now();

    final ct = data['createTime'] as String?;
    if (ct != null) memo.createdAt = DateTime.parse(ct).toLocal();

    final ut = data['updateTime'] as String?;
    if (ut != null) memo.updatedAt = DateTime.parse(ut).toLocal();

    return memo;
  }

  static void _applyRemoteData(
      MemoEntry memo, Map<String, dynamic> data) {
    memo.content = data['content'] as String? ?? '';
    final ut = data['updateTime'] as String?;
    if (ut != null) memo.updatedAt = DateTime.parse(ut).toLocal();
    memo
      ..syncStatus = SyncStatus.synced
      ..lastSyncAt = DateTime.now();
  }
}
