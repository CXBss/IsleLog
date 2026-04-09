import 'package:isar/isar.dart';

import 'memo_entry.dart';

part 'folder_entry.g.dart';

/// 文件夹本地数据模型
///
/// 对应服务端 folders 表，用于组织文章。支持全离线操作。
/// 删除文件夹时客户端同步将子文件夹和文章的 parent 置 null（与服务端行为一致）。
@collection
class FolderEntry {
  /// 本地自增主键
  Id id = Isar.autoIncrement;

  /// 远端资源名，格式为 "folders/{id}"，未同步时为 null
  ///
  /// 不设 unique 索引：未同步的文件夹 folderName 均为 null，
  /// unique 对 null 值有冲突问题（Isar 会将多个 null 视为重复键）。
  @Index()
  String? folderName;

  /// 文件夹标题
  String title = '';

  /// 父文件夹远端资源名，null 表示根目录
  String? parentFolderName;

  /// 离线关联父文件夹的本地 id（parentFolderName 有值后不再使用）
  int? localParentFolderId;

  /// 软删除标记
  bool isDeleted = false;

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 最后更新时间
  DateTime updatedAt = DateTime.now();

  /// 同步状态
  @enumerated
  SyncStatus syncStatus = SyncStatus.pending;

  /// 最后一次成功同步时间
  DateTime? lastSyncAt;
}
