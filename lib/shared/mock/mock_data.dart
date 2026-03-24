import '../../data/models/memo_entry.dart';

/// 用于 UI 开发阶段的假数据（覆盖多天以展示时间线和日历高亮）
final List<MemoEntry> mockMemos = [
  _make(
    id: 1,
    content: '今天读了《原则》第三章，作者关于"极度透明"的观点很有启发。\n\n'
        '> 生活和工作的原则，是在反复实践中形成的，而不是一开始就拥有的。\n\n'
        '#想法 #读书',
    createdAt: DateTime(2025, 12, 11, 14, 6),
    tags: ['想法', '读书'],
    location: '江苏省-苏州市-工业园区',
  ),
  _make(
    id: 2,
    content: '早上跑步 5 公里，配速 6\'20"，感觉状态不错 💪\n\n#运动 #生活记录',
    createdAt: DateTime(2025, 12, 11, 7, 33),
    tags: ['运动', '生活记录'],
  ),
  _make(
    id: 3,
    content: '和同事讨论了新项目技术选型，决定用 **Flutter + Rust** 的方案。\n\n'
        '主要考虑跨平台 + 高性能的需求，后续值得深入研究。\n\n'
        '#工作 #编程 #Flutter',
    createdAt: DateTime(2025, 12, 10, 16, 45),
    tags: ['工作', '编程', 'Flutter'],
    location: '江苏省-苏州市-独墅湖科教创新区',
  ),
  _make(
    id: 4,
    content: '晚上做了一顿红烧肉，第一次做出了妈妈的味道 🍖\n\n'
        '秘诀是提前用冰糖炒糖色，火候很关键。\n\n#美食 #生活记录',
    createdAt: DateTime(2025, 12, 10, 20, 12),
    tags: ['美食', '生活记录'],
  ),
  _make(
    id: 5,
    content: '看了《奥本海默》，震撼！\n\n'
        '> "Now I am become Death, the destroyer of worlds."\n\n'
        '三个小时的片长不觉得长，诺兰的叙事方式真的很厉害。\n\n#电影 #娱乐',
    createdAt: DateTime(2025, 12, 9, 21, 30),
    tags: ['电影', '娱乐'],
    location: '苏州市-万象城影院',
  ),
  _make(
    id: 6,
    content: '周末爬了天平山，秋叶正红，美不胜收 🍁\n\n'
        '下山的路遇到一只野猫，陪我走了一段路，很治愈。\n\n'
        '#户外 #生活记录 #周末',
    createdAt: DateTime(2025, 12, 7, 10, 0),
    tags: ['户外', '生活记录', '周末'],
    location: '苏州天平山风景区',
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
