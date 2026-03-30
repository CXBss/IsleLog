import 'package:isar/isar.dart';

import 'memo_entry.dart';

part 'comment_entry.g.dart';

/// 评论本地数据模型
///
/// 评论在 Memos 服务端本质上也是 memo，通过 parent 字段关联到父 memo。
/// 本地用独立的 collection 存储，与 MemoEntry 分开管理。
@collection
class CommentEntry {
  /// 本地自增主键
  Id id = Isar.autoIncrement;

  /// 评论自身的远端资源名，格式 "memos/{id}"，未同步时为 null
  @Index()
  String? memosName;

  /// 所属日记的远端资源名（父 memo 的 memosName）
  @Index()
  String? parentMemosName;

  /// 所属日记的本地 id（用于离线关联，无 parentMemosName 时使用）
  @Index()
  int? memoId;

  /// 评论内容（支持 Markdown）
  String content = '';

  /// 评论作者名，格式 "users/{id}"，离线创建时为空字符串
  String creatorName = '';

  /// 地理位置文本（自动获取，可为 null）
  String? location;

  /// 创建时间
  @Index()
  DateTime createdAt = DateTime.now();

  /// 最后更新时间
  DateTime updatedAt = DateTime.now();

  /// 同步状态
  @enumerated
  SyncStatus syncStatus = SyncStatus.pending;

  /// 最后一次成功同步时间
  DateTime? lastSyncAt;

  /// 软删除标记
  bool isDeleted = false;
}
