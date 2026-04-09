import 'package:isar/isar.dart';

import 'attachment_info.dart';
import 'memo_entry.dart';

part 'article_entry.g.dart';

/// 文章本地数据模型
///
/// 底层对应服务端 memos 表的 type='ARTICLE' 记录，通过独立接口集管理。
/// 与 MemoEntry 完全独立，支持全离线操作——写本地 Isar 后联网同步。
@collection
class ArticleEntry {
  /// 本地自增主键
  Id id = Isar.autoIncrement;

  /// 远端资源名，格式为 "articles/{id}"，未同步时为 null
  ///
  /// 不设 unique 索引：未同步的文章 articleName 均为 null，
  /// unique 会导致多条离线文章互相覆盖。
  @Index()
  String? articleName;

  /// 文章标题（对应 API title 字段，独立于正文）
  String title = '';

  /// 正文内容（Markdown）
  String content = '';

  /// 所属文件夹远端资源名，如 "folders/111"，null 表示根目录
  ///
  /// 离线创建文件夹时此字段为 null，用 [localFolderId] 关联本地文件夹，
  /// 文件夹同步上传后自动填充此字段。
  String? folderName;

  /// 离线关联文件夹的本地 id（folderName 有值后此字段不再使用）
  ///
  /// 离线新建文章并选择了一个尚未同步的文件夹时，通过此字段关联，
  /// push 时先确认文件夹已同步（有 folderName），再填入文章请求体。
  int? localFolderId;

  /// 可见性：PRIVATE / PROTECTED / PUBLIC
  String visibility = 'PRIVATE';

  /// 置顶标记
  bool isPinned = false;

  /// 软删除标记
  bool isDeleted = false;

  /// 归档标记
  bool isArchived = false;

  /// 创建时间（带索引，用于列表排序）
  @Index()
  DateTime createdAt = DateTime.now();

  /// 最后更新时间
  DateTime updatedAt = DateTime.now();

  /// 同步状态
  @enumerated
  SyncStatus syncStatus = SyncStatus.pending;

  /// 最后一次成功同步时间
  DateTime? lastSyncAt;

  /// 冲突时保存的远端 content（null 表示无冲突）
  String? conflictRemoteContent;

  /// 冲突时保存的远端 title
  String? conflictRemoteTitle;

  /// 附件列表（JSON 字符串数组，每项为一个 AttachmentInfo 的 JSON）
  List<String> attachmentsJson = [];
}

/// [ArticleEntry] 附件读写扩展
extension ArticleEntryAttachmentExt on ArticleEntry {
  List<AttachmentInfo> get attachments =>
      attachmentsJson.map(AttachmentInfo.fromJsonString).toList();

  set attachments(List<AttachmentInfo> list) =>
      attachmentsJson = list.map((a) => a.toJsonString()).toList();
}
