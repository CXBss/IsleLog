import 'package:isle_log/data/database/database_service.dart';

/// 在正文末尾追加缺失的已选标签。
///
/// 使用与 [DatabaseService.extractTags] 相同的规则提取现有标签并去重，
/// 只在末尾追加不存在的标签；没有新标签时正文逐字不变。
String insertSelectedTags(String content, List<String> selectedTags) {
  final existing = DatabaseService.extractTags(content);
  final missing = selectedTags.toSet().where((t) => !existing.contains(t));
  if (missing.isEmpty) return content;
  final suffix = missing.map((t) => '#$t').join(' ');
  final trimmed = content.trimRight();
  if (trimmed.isEmpty) return suffix;
  return '$trimmed\n\n$suffix';
}
