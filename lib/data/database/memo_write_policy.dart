import '../models/memo_entry.dart';

/// 防止持有旧快照的 UI 对象清空已经写入数据库的远端资源名。
void preserveRemoteIdentity(MemoEntry incoming, MemoEntry? stored) {
  if (incoming.memosName == null && stored?.memosName != null) {
    incoming.memosName = stored!.memosName;
  }
}

/// 将附件上传后的请求数据写入仍处于同一编辑版本的本地记录。
bool mergePreparedMemoForPush(MemoEntry latest, MemoEntry prepared) {
  if (latest.updatedAt != prepared.updatedAt) return false;

  latest
    ..content = prepared.content
    ..attachmentsJson = List<String>.of(prepared.attachmentsJson);
  return true;
}

/// 合并一次成功 Push 的结果到当前最新本地记录。
///
/// [submitted] 是网络请求实际提交的快照，[latest] 是请求完成后重新读取的
/// 本地记录。两者更新时间一致表示请求期间没有新的用户编辑。
void reconcileMemoPushSuccess({
  required MemoEntry latest,
  required MemoEntry submitted,
  String? remoteName,
  DateTime? syncedAt,
  bool? moodWeatherSynced,
}) {
  latest.memosName ??= remoteName ?? submitted.memosName;
  latest.lastSyncAt = syncedAt ?? DateTime.now();

  // 远端现在等于 submitted，记录本次是否把真实的 mood/weather 推了上去：
  // - true  → 远端现在有值，将来本地清空需显式推 0 才能同步清除；
  // - false → 远端已无值（没推或推的就是清空），无需再动。
  // 两个分支都要更新：即便请求期间又有新编辑，远端状态仍由本次 submitted 决定。
  if (moodWeatherSynced != null) {
    latest.moodWeatherSynced = moodWeatherSynced;
  }

  if (mergePreparedMemoForPush(latest, submitted)) {
    // 附件上传会更新正文 URL 和附件资源名，需要将实际提交的数据落盘。
    latest
      ..syncStatus = SyncStatus.synced
      ..originalContent = null
      ..conflictRemoteContent = null;
    return;
  }

  // 请求期间又发生了编辑：远端目前等于 submitted，本地最新版本稍后继续 Push。
  latest
    ..syncStatus = SyncStatus.pending
    ..originalContent = submitted.content
    ..conflictRemoteContent = null;
}
