import 'package:isar/isar.dart';

part 'tag_stat.g.dart';

/// 标签统计本地缓存
///
/// 存储标签名及其关联的日记数量，作为远端 [/api/v1/users/{user}:getStats] 的本地镜像。
/// 联网时从 API 刷新，离线时直接读本地。
@collection
class TagStat {
  Id id = Isar.autoIncrement;

  /// 标签名（不含 '#'）
  @Index(unique: true, replace: true)
  String name = '';

  /// 该标签关联的日记数量
  int count = 0;

  TagStat();

  TagStat.of(this.name, this.count);
}
