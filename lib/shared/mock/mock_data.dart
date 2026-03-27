import '../../data/models/memo_entry.dart';

/// 用于 UI 开发阶段的假数据（覆盖多天以展示时间线和日历高亮）
final List<MemoEntry> mockMemos = [
  _make(
    id: 2,
    content: '早上跑步 5 公里，配速 6\'20"，感觉状态不错 💪\n\n#运动 #生活记录',
    createdAt: DateTime(2025, 12, 11, 7, 33),
    tags: ['运动', '生活记录'],
  ),
  _make(
    id: 7,
    content: '本周总结：\n\n'
        '- ✅ 完成项目文档初稿\n'
        '- ✅ 读书 3 章\n'
        '- ✅ 跑步 2 次\n'
        '- ❌ 健身计划落后，下周补上\n\n'
        '整体还不错，继续保持！\n\n#周总结 #想法',
    createdAt: DateTime(2025, 12, 7, 22, 0),
    tags: ['周总结', '想法'],
  ),
];

MemoEntry _make({
  required int id,
  required String content,
  required DateTime createdAt,
  required List<String> tags,
  String? location,
}) =>
    MemoEntry()
      ..id = id
      ..memosName = 'memos/$id'
      ..content = content
      ..createdAt = createdAt
      ..updatedAt = createdAt
      ..tags = tags
      ..location = location
      ..syncStatus = SyncStatus.synced;
