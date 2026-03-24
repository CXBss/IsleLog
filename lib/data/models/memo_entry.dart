import 'package:isar/isar.dart';

part 'memo_entry.g.dart';

/// 同步状态
enum SyncStatus {
  pending,  // 待同步（本地有改动未推送）
  synced,   // 已同步
  conflict, // 有冲突（本地与远端均有修改）
}

/// 日记/备忘录本地数据模型
@collection
class MemoEntry {
  /// 本地自增主键
  Id id = Isar.autoIncrement;

  /// 远端 Memos 资源名，格式为 "memos/{id}"，未同步时为 null
  /// 仅建普通索引（供按 memosName 快速查找），不设 unique——
  /// 未同步的本地日记 memosName 均为 null，unique+replace 会导致互相覆盖
  @Index()
  String? memosName;

  /// 正文内容（支持 Markdown 和 #标签）
  String content = '';

  /// 创建时间（带索引，用于时间线排序）
  @Index()
  DateTime createdAt = DateTime.now();

  /// 最后更新时间
  DateTime updatedAt = DateTime.now();

  /// 从 content 中解析出的标签列表（不含 '#'，带元素索引）
  ///
  /// 建立 value 类型索引以支持高效的标签聚合统计和分类筛选
  @Index(type: IndexType.value)
  List<String> tags = [];

  /// 位置信息（可选）
  String? location;

  /// 同步状态
  @enumerated
  SyncStatus syncStatus = SyncStatus.pending;

  /// 最后一次成功同步时间
  DateTime? lastSyncAt;

  /// 软删除标记（本地删除但尚未同步到远端时为 true）
  bool isDeleted = false;
}
