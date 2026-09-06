import 'package:isar/isar.dart';

import 'memo_entry.dart';

part 'thread_entry.g.dart';

/// 事件串状态。
enum ThreadStatus { active, resolved }

/// 事件串本地数据模型。
///
/// 成员按对应日记的创建时间排序；不额外存储手工顺序，避免与日记改期冲突。
@collection
class ThreadEntry {
  Id id = Isar.autoIncrement;

  /// 远端资源名，格式为 `threads/{id}`；未同步时为 null。
  @Index()
  String? threadName;

  String title = '';
  String summary = '';
  bool summaryIsManual = false;

  /// 锁定后 AI 不再改写简介
  ///
  /// 与 [summaryIsManual] 是两件事：后者记录「谁写的」仅供展示，前者决定
  /// 「AI 能不能改」。分开是因为用户可能想冻结一条 AI 写得不错的简介，
  /// 而不必把它原样重打一遍。
  bool summaryLocked = false;

  @enumerated
  ThreadStatus status = ThreadStatus.active;

  /// 成员日记的本地 id，支持按日记反查其所属事件串。
  @Index(type: IndexType.value)
  List<int> memberLocalIds = [];

  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();

  @enumerated
  SyncStatus syncStatus = SyncStatus.pending;

  DateTime? lastSyncAt;
  bool isDeleted = false;
}
