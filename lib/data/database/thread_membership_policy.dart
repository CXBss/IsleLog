import '../models/memo_entry.dart';
import '../models/thread_entry.dart';

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
