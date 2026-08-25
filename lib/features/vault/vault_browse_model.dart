import '../../data/models/memo_entry.dart';
import '../../data/models/vault_entry.dart';

/// 浏览范围：全部（主库 + vault）还是只看 vault。
enum VaultScope { all, vaultOnly }

/// 时间线上的一条记录，抹平「主库日记」和「vault 条目」的差异。
///
/// UI 只需要按 [isVault] 决定渲染成哪种卡片，筛选和分组逻辑对两者一视同仁。
sealed class VaultBrowseItem {
  DateTime get time;
  String get content;
  List<String> get tags;
  bool get isVault;
}

class VaultBrowseMemo extends VaultBrowseItem {
  final MemoEntry memo;
  VaultBrowseMemo(this.memo);

  @override
  DateTime get time => memo.createdAt;
  @override
  String get content => memo.content;
  @override
  List<String> get tags => memo.tags;
  @override
  bool get isVault => false;
}

class VaultBrowseVaultItem extends VaultBrowseItem {
  final VaultEntry entry;
  VaultBrowseVaultItem(this.entry);

  @override
  DateTime get time => entry.createdAt;
  @override
  String get content => entry.content;
  @override
  List<String> get tags => entry.tags;
  @override
  bool get isVault => true;
}

/// 四个可叠加的筛选条件。它们不是互斥模式——搜索、日期、标签、范围
/// 可以任意组合，[VaultBrowseModel.apply] 依次全部应用。
class VaultBrowseFilter {
  /// 正文关键词，空白视为不过滤
  final String query;

  /// 只看某一天（忽略时分秒），null 表示不限
  final DateTime? day;

  /// 只看含该标签的条目，null 表示不限
  final String? tag;

  final VaultScope scope;

  const VaultBrowseFilter({
    this.query = '',
    this.day,
    this.tag,
    this.scope = VaultScope.all,
  });

  VaultBrowseFilter copyWith({
    String? query,
    DateTime? day,
    bool clearDay = false,
    String? tag,
    bool clearTag = false,
    VaultScope? scope,
  }) {
    return VaultBrowseFilter(
      query: query ?? this.query,
      day: clearDay ? null : (day ?? this.day),
      tag: clearTag ? null : (tag ?? this.tag),
      scope: scope ?? this.scope,
    );
  }

  bool get hasAnyFilter =>
      query.trim().isNotEmpty || day != null || tag != null;
}

/// 隐私空间浏览的纯逻辑：合并两个数据源、应用筛选、分组、统计。
///
/// 刻意不碰 UI 也不碰磁盘——调用方把已加载的主库日记和已解密的 vault 条目
/// 传进来即可。这样四个筛选条件的组合行为可以直接单测，不用起 widget test。
class VaultBrowseModel {
  VaultBrowseModel._();

  /// 合并两个来源并应用全部筛选，结果按时间倒序。
  static List<VaultBrowseItem> apply({
    required List<MemoEntry> memos,
    required List<VaultEntry> entries,
    required VaultBrowseFilter filter,
  }) {
    final items = <VaultBrowseItem>[
      if (filter.scope == VaultScope.all) ...memos.map(VaultBrowseMemo.new),
      ...entries.map(VaultBrowseVaultItem.new),
    ];

    final query = filter.query.trim().toLowerCase();
    final result = items.where((item) {
      if (query.isNotEmpty && !item.content.toLowerCase().contains(query)) {
        return false;
      }
      if (filter.day != null && !_isSameDay(item.time, filter.day!)) {
        return false;
      }
      if (filter.tag != null && !item.tags.contains(filter.tag)) {
        return false;
      }
      return true;
    }).toList();

    result.sort((a, b) => b.time.compareTo(a.time));
    return result;
  }

  /// 按天分组，返回 (yyyy-MM-dd, 当天条目) 列表，组按日期倒序。
  ///
  /// 与主页 home_view 的 _groupByDay 保持一致的观感。
  /// 传入的列表应已按时间倒序（[apply] 的输出即满足），组内顺序沿用之。
  static List<(String, List<VaultBrowseItem>)> groupByDay(
    List<VaultBrowseItem> items,
  ) {
    final map = <String, List<VaultBrowseItem>>{};
    for (final item in items) {
      map.putIfAbsent(dayKey(item.time), () => []).add(item);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.map((k) => (k, map[k]!)).toList();
  }

  /// 合并两个来源的标签计数。
  ///
  /// ⚠️ 结果只用于隐私空间内的展示，**绝不能写回主库的 TagStat 表**——
  /// 那会让 vault 的标签出现在主页侧边栏里。
  static Map<String, int> tagCounts({
    required List<MemoEntry> memos,
    required List<VaultEntry> entries,
    required VaultScope scope,
  }) {
    final counts = <String, int>{};
    void add(List<String> tags) {
      for (final tag in tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }

    if (scope == VaultScope.all) {
      for (final m in memos) {
        add(m.tags);
      }
    }
    for (final e in entries) {
      add(e.tags);
    }
    return counts;
  }

  /// 指定月份内有记录的日号集合，供日历高亮。
  static Set<int> daysWithEntriesInMonth({
    required List<MemoEntry> memos,
    required List<VaultEntry> entries,
    required VaultScope scope,
    required int year,
    required int month,
  }) {
    final days = <int>{};
    void add(DateTime t) {
      if (t.year == year && t.month == month) days.add(t.day);
    }

    if (scope == VaultScope.all) {
      for (final m in memos) {
        add(m.createdAt);
      }
    }
    for (final e in entries) {
      add(e.createdAt);
    }
    return days;
  }

  static String dayKey(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}';

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _two(int v) => v.toString().padLeft(2, '0');
}
