import 'package:isar/isar.dart';

import 'attachment_info.dart';

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

  /// 位置信息（可选，地址文本）
  String? location;

  /// 纬度（可选，与 location 配套存储，用于跳转地图）
  double? latitude;

  /// 经度（可选，与 location 配套存储，用于跳转地图）
  double? longitude;

  /// 同步状态
  @enumerated
  SyncStatus syncStatus = SyncStatus.pending;

  /// 最后一次成功同步时间
  DateTime? lastSyncAt;

  /// 软删除标记（本地删除但尚未同步到远端时为 true）
  bool isDeleted = false;

  /// 归档标记（归档的 memo 不在时间线显示）
  bool isArchived = false;

  /// 置顶标记（pinned 的 memo 在时间线最顶部显示）
  bool isPinned = false;

  /// 附件列表（JSON 字符串数组，每项为一个 [AttachmentInfo] 的 JSON）
  ///
  /// 不建索引，通过扩展方法 [MemoEntryAttachmentExt] 读写强类型列表。
  List<String> attachmentsJson = [];

  /// 冲突时保存的远端版本内容（null 表示无冲突）
  ///
  /// Pull 时检测到本地 pending、远端也有更新，则将远端内容存入此字段，
  /// 同时保持本地 content 不变，syncStatus 置为 conflict。
  /// 用户编辑保存后清空此字段，syncStatus 改回 pending。
  String? conflictRemoteContent;
}

/// [MemoEntry] 附件读写扩展
///
/// Isar codegen 不支持 collection class 内的自定义 getter/setter，
/// 因此将强类型附件操作单独放在扩展中。
extension MemoEntryAttachmentExt on MemoEntry {
  /// 读取附件列表（反序列化）
  List<AttachmentInfo> get attachments =>
      attachmentsJson.map(AttachmentInfo.fromJsonString).toList();

  /// 写入附件列表（序列化）
  set attachments(List<AttachmentInfo> list) =>
      attachmentsJson = list.map((a) => a.toJsonString()).toList();
}
