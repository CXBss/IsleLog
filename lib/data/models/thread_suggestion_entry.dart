import 'package:isar/isar.dart';

import 'memo_entry.dart';

part 'thread_suggestion_entry.g.dart';

/// 建议状态
enum SuggestionStatus { pending, accepted, dismissed }

/// AI 产出的事件串归属建议
///
/// 服务端只对置信度 ≥ 0.7 的匹配入库，因此本地不需要按置信度分档展示。
@collection
class ThreadSuggestionEntry {
  Id id = Isar.autoIncrement;

  /// 远端资源名 "threadSuggestions/{id}"，不设 unique（同 memosName 的理由）
  @Index()
  String? suggestionName;

  /// 建议关联的日记本地 id；value 索引供时间线卡片反查
  @Index()
  int memoLocalId = 0;

  /// 建议归入的事件串本地 id
  int threadLocalId = 0;

  double confidence = 0;
  String reason = '';

  @enumerated
  SuggestionStatus status = SuggestionStatus.pending;

  DateTime createdAt = DateTime.now();

  /// 本地已操作但尚未推送时为 pending，拉取时不会被服务端旧状态覆盖
  @enumerated
  SyncStatus syncStatus = SyncStatus.synced;
}
