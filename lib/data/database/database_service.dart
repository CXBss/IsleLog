import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/memo_entry.dart';

/// 本地数据库服务（单例）
///
/// 封装 Isar 数据库的 CRUD 操作，所有写操作在保存前自动提取标签。
class DatabaseService {
  DatabaseService._();

  static Isar? _isar;

  /// 获取已初始化的 Isar 实例（懒加载）
  static Future<Isar> get db async {
    return _isar ??= await _open();
  }

  static Future<Isar> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    return Isar.open(
      [MemoEntrySchema],
      directory: dir.path,
    );
  }

  // ────────────────────────────────────────────────────────────────
  // 写操作
  // ────────────────────────────────────────────────────────────────

  /// 新建或更新一条日记。
  ///
  /// 写入前自动解析标签并更新 [MemoEntry.tags]。
  /// [skipTimestamp] 为 true 时不修改 [MemoEntry.updatedAt]（同步场景使用）。
  /// 返回本地主键 id。
  static Future<int> saveMemo(MemoEntry memo,
      {bool skipTimestamp = false}) async {
    final isar = await db;
    memo.tags = extractTags(memo.content);
    if (!skipTimestamp) memo.updatedAt = DateTime.now();
    return isar.writeTxn(() => isar.memoEntrys.put(memo));
  }

  /// 软删除（将 isDeleted 置为 true，syncStatus 置为 pending）。
  static Future<void> softDelete(int id) async {
    final isar = await db;
    final memo = await isar.memoEntrys.get(id);
    if (memo == null) return;
    await isar.writeTxn(() async {
      memo.isDeleted = true;
      memo.syncStatus = SyncStatus.pending;
      memo.updatedAt = DateTime.now();
      await isar.memoEntrys.put(memo);
    });
  }

  /// 物理删除（仅用于已确认远端同步删除后的清理）。
  static Future<bool> hardDelete(int id) async {
    final isar = await db;
    return isar.writeTxn(() => isar.memoEntrys.delete(id));
  }

  // ────────────────────────────────────────────────────────────────
  // 读操作
  // ────────────────────────────────────────────────────────────────

  /// 获取所有未删除的日记，按创建时间倒序。
  static Future<List<MemoEntry>> getAllMemos() async {
    final isar = await db;
    return isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .sortByCreatedAtDesc()
        .findAll();
  }

  /// 根据本地 id 获取单条日记。
  static Future<MemoEntry?> getMemoById(int id) async {
    final isar = await db;
    return isar.memoEntrys.get(id);
  }

  /// 根据远端资源名获取日记。
  static Future<MemoEntry?> getMemoByMemosName(String memosName) async {
    final isar = await db;
    return isar.memoEntrys
        .filter()
        .memosNameEqualTo(memosName)
        .findFirst();
  }

  /// 获取指定日期当天的所有未删除日记，按创建时间倒序。
  static Future<List<MemoEntry>> getMemosByDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final isar = await db;
    return isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .createdAtBetween(start, end)
        .sortByCreatedAtDesc()
        .findAll();
  }

  /// 获取指定标签的所有未删除日记，按创建时间倒序。
  static Future<List<MemoEntry>> getMemosByTag(String tag) async {
    final isar = await db;
    return isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .tagsElementEqualTo(tag)
        .sortByCreatedAtDesc()
        .findAll();
  }

  /// 获取所有待同步（pending）的日记（含软删除条目）。
  static Future<List<MemoEntry>> getPendingSyncMemos() async {
    final isar = await db;
    return isar.memoEntrys
        .filter()
        .syncStatusEqualTo(SyncStatus.pending)
        .findAll();
  }

  /// 统计所有标签的出现次数，返回 {tagName: count} 映射。
  static Future<Map<String, int>> getAllTagCounts() async {
    final memos = await getAllMemos();
    final counts = <String, int>{};
    for (final memo in memos) {
      for (final tag in memo.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// 获取有日记的日期集合（用于日历视图高亮）。
  static Future<Set<DateTime>> getDatesWithMemos() async {
    final memos = await getAllMemos();
    return memos
        .map((m) => DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day))
        .toSet();
  }

  // ────────────────────────────────────────────────────────────────
  // 响应式 Stream
  // ────────────────────────────────────────────────────────────────

  /// 监听所有未删除日记的变化，每次 DB 写操作后自动推送最新列表。
  ///
  /// [fireImmediately] = true 表示订阅时立即推送当前数据。
  static Future<Stream<List<MemoEntry>>> watchAllMemos() async {
    final isar = await db;
    return isar.memoEntrys
        .watchLazy(fireImmediately: true)
        .asyncMap((_) => getAllMemos());
  }

  // ────────────────────────────────────────────────────────────────
  // 首次启动播种
  // ────────────────────────────────────────────────────────────────

  /// 若数据库为空，批量写入 [seeds] 作为演示数据。
  static Future<void> seedIfEmpty(List<MemoEntry> seeds) async {
    final isar = await db;
    final count = await isar.memoEntrys.count();
    if (count > 0) return;
    await isar.writeTxn(() async {
      for (final memo in seeds) {
        await isar.memoEntrys.put(memo);
      }
    });
  }

  // ────────────────────────────────────────────────────────────────
  // 工具方法
  // ────────────────────────────────────────────────────────────────

  /// 从正文中提取 Memos 风格的标签（兼容 ASCII 和中文，支持 tag/subtag 嵌套格式）。
  ///
  /// 示例：`"今天 #想法 #work/project"` → `["想法", "work/project"]`
  static List<String> extractTags(String content) {
    // 匹配 # 后跟非空白非 # 字符（支持中文、斜杠嵌套路径）
    final regex = RegExp(r'(?<!\S)#([^\s#]+)');
    return regex
        .allMatches(content)
        .map((m) => m.group(1)!)
        .where((tag) => tag.isNotEmpty)
        .toList();
  }
}
