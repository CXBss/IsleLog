import 'package:flutter/foundation.dart';

import '../../data/models/memo_entry.dart';

/// 判断时间线中的对象快照是否等价。
///
/// 同步写入通常不会修改 updatedAt，因此还需比较远端身份、同步状态和附件等字段。
bool memoListsMatchForDisplay(List<MemoEntry> a, List<MemoEntry> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final left = a[i];
    final right = b[i];
    if (left.id != right.id ||
        left.memosName != right.memosName ||
        left.content != right.content ||
        left.createdAt != right.createdAt ||
        left.updatedAt != right.updatedAt ||
        left.syncStatus != right.syncStatus ||
        left.lastSyncAt != right.lastSyncAt ||
        left.isDeleted != right.isDeleted ||
        left.isArchived != right.isArchived ||
        left.isPinned != right.isPinned ||
        left.location != right.location ||
        left.latitude != right.latitude ||
        left.longitude != right.longitude ||
        left.conflictRemoteContent != right.conflictRemoteContent ||
        left.originalContent != right.originalContent ||
        left.todoStatus != right.todoStatus ||
        left.pendingTodoCount != right.pendingTodoCount ||
        !listEquals(left.tags, right.tags) ||
        !listEquals(left.attachmentsJson, right.attachmentsJson)) {
      return false;
    }
  }
  return true;
}
