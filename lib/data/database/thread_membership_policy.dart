import '../models/memo_entry.dart';
import '../models/thread_entry.dart';
import '../models/thread_suggestion_entry.dart';

/// Pull 时对事件串采取的动作。
enum ThreadPullAction { insert, overwrite, markConflict, skip }

/// 按事件串整体的更新时间判断远端数据如何合并。
ThreadPullAction decideThreadPull({
  required ThreadEntry? local,
  required DateTime remoteUpdatedAt,
}) {
  if (local == null) return ThreadPullAction.insert;
  switch (local.syncStatus) {
    case SyncStatus.synced:
      return ThreadPullAction.overwrite;
    case SyncStatus.conflict:
      return ThreadPullAction.skip;
    case SyncStatus.pending:
      return remoteUpdatedAt.isAfter(local.updatedAt)
          ? ThreadPullAction.markConflict
          : ThreadPullAction.skip;
  }
}

/// 在成员列表中加入或移除一篇日记，始终返回**新的可增长列表**。
///
/// 必须复制而不能原地改：Isar 反序列化 `List<int>` 得到的是定长的 `Int64List`，
/// 对它调用 add/remove 会抛 "Cannot add to a fixed-length list"。这类异常若发生在
/// 异步回调里会被静默吞掉，表现为「点了没反应」而不是崩溃，很难排查。
List<int> toggleThreadMember(
  List<int> members,
  int memoLocalId, {
  required bool selected,
}) {
  final next = List<int>.from(members);
  if (selected) {
    if (!next.contains(memoLocalId)) next.add(memoLocalId);
  } else {
    next.remove(memoLocalId);
  }
  return next;
}

/// 本地成员映射为远端资源名的结果。
class ThreadMemberResolution {
  final List<String> memoNames;
  final bool complete;

  const ThreadMemberResolution({
    required this.memoNames,
    required this.complete,
  });
}

/// 将成员本地 id 映射为已同步的日记资源名。
ThreadMemberResolution resolveThreadMemberNames(
  List<int> memberLocalIds,
  Map<int, String?> memosNameByLocalId,
) {
  final names = <String>[];
  var complete = true;
  for (final id in memberLocalIds) {
    final name = memosNameByLocalId[id];
    if (name == null || name.isEmpty) {
      complete = false;
    } else {
      names.add(name);
    }
  }
  return ThreadMemberResolution(memoNames: names, complete: complete);
}

/// 将远端成员名映射为本地 id，本地尚未拉取的成员会在下轮同步补齐。
List<int> mapRemoteMembersToLocalIds(
  List<String> memoNames,
  Map<String, int> localIdByMemosName,
) => [
  for (final name in memoNames)
    if (localIdByMemosName[name] case final id?) id,
];

/// 判断拉取到的远端建议是否可以覆盖本地记录。
///
/// 本地已操作但尚未推送（`syncStatus == pending`）时必须保留：服务端此刻
/// 仍是 `PENDING`，覆盖会让用户离线点过的「加入」或「忽略」凭空复活。
bool shouldOverwriteSuggestion(ThreadSuggestionEntry? local) {
  if (local == null) return true;
  return local.syncStatus == SyncStatus.synced;
}

/// 一条待展示建议及其（可能尚未解析出，或指向的记录已不存在的）
/// memo / thread。调用方负责用异步的 [DatabaseService] 查询填充这两项，
/// 这里只做纯过滤，不发起任何数据库调用。
class SuggestionResolution {
  final ThreadSuggestionEntry suggestion;
  final MemoEntry? memo;
  final ThreadEntry? thread;

  const SuggestionResolution({
    required this.suggestion,
    required this.memo,
    required this.thread,
  });
}

/// 过滤掉 memo/thread 已不存在或已被软删除的建议。
///
/// 返回的 `kept`（建议本体）与 `resolved`（对应已解析出的 memo/thread）
/// 严格按下标一一对应——调用方据此拼出展示用列表（如 UI 层的
/// `SuggestionItem`）后，两个列表的长度和顺序必须始终一致，否则
/// 界面上按下标回调的「接受/忽略」会作用到错误的那一条建议。
({List<ThreadSuggestionEntry> kept, List<(MemoEntry, ThreadEntry)> resolved})
buildAlignedSuggestions(List<SuggestionResolution> resolutions) {
  final kept = <ThreadSuggestionEntry>[];
  final resolved = <(MemoEntry, ThreadEntry)>[];
  for (final r in resolutions) {
    final memo = r.memo;
    final thread = r.thread;
    if (memo == null || thread == null || memo.isDeleted || thread.isDeleted) {
      continue;
    }
    kept.add(r.suggestion);
    resolved.add((memo, thread));
  }
  return (kept: kept, resolved: resolved);
}

/// 判断某个事件串是否需要修复「升级后手写简介被静默解锁」问题。
///
/// `summaryLocked` 是随本次改动新增的字段，旧版本升级后所有已有事件串
/// 该字段默认为 false——即使 `summaryIsManual == true`（用户手写过简介，
/// 服务端早已为这种情况回填 `summary_locked = 1`）。命中时需要补一次本地
/// 修复：锁定 + 转为 pending，以便下次同步把修正值推送回服务端，否则这份
/// 过期的 false 可能在下次编辑时被推送上去，悄悄解锁受保护的简介。
bool needsManualSummaryLockRepair(ThreadEntry thread) =>
    thread.summaryIsManual && !thread.summaryLocked;
