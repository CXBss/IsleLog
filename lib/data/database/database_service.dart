import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

import '../models/comment_entry.dart';
import '../models/memo_entry.dart';
import '../models/tag_stat.dart';

/// 本地数据库服务（单例）
///
/// 封装 Isar 数据库的 CRUD 操作，所有写操作在保存前自动提取标签。
/// 通过静态方法对外暴露接口，内部使用懒加载单例保证只开一个 DB 实例。
class DatabaseService {
  DatabaseService._();

  /// 持有唯一 Isar 实例（null 表示尚未初始化）
  static Isar? _isar;

  /// 获取已初始化的 Isar 实例（懒加载，首次调用时打开数据库）
  static Future<Isar> get db async {
    return _isar ??= await _open();
  }

  /// 打开数据库文件
  static Future<Isar> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    debugPrint('[DB] 打开数据库，路径：${dir.path}');
    final isar = await Isar.open(
      [MemoEntrySchema, TagStatSchema, CommentEntrySchema],
      directory: dir.path,
      inspector: true,
    );
    debugPrint('[DB] 数据库已就绪');
    return isar;
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
    // 每次保存前重新解析正文中的标签
    memo.tags = extractTags(memo.content);
    if (!skipTimestamp) memo.updatedAt = DateTime.now();
    final id = await isar.writeTxn(() => isar.memoEntrys.put(memo));
    debugPrint(
        '[DB] saveMemo → id=$id, tags=${memo.tags}, skipTimestamp=$skipTimestamp');
    return id;
  }

  /// 软删除（将 isDeleted 置为 true，syncStatus 置为 pending）。
  ///
  /// 软删除后条目仍保留在数据库，等待下次同步时推送删除到远端，
  /// 确认远端删除成功后再执行 [hardDelete]。
  static Future<void> softDelete(int id) async {
    final isar = await db;
    final memo = await isar.memoEntrys.get(id);
    if (memo == null) {
      debugPrint('[DB] softDelete: id=$id 不存在，跳过');
      return;
    }
    await isar.writeTxn(() async {
      memo.isDeleted = true;
      memo.syncStatus = SyncStatus.pending;
      memo.updatedAt = DateTime.now();
      await isar.memoEntrys.put(memo);
    });
    debugPrint('[DB] softDelete: id=$id 已标记软删除');
  }

  /// 物理删除（仅用于已确认远端同步删除后的清理）。
  ///
  /// ⚠️ 物理删除不可恢复，调用前请确认远端已同步删除。
  static Future<bool> hardDelete(int id) async {
    final isar = await db;
    final deleted = await isar.writeTxn(() => isar.memoEntrys.delete(id));
    debugPrint('[DB] hardDelete: id=$id, 成功=$deleted');
    return deleted;
  }

  // ────────────────────────────────────────────────────────────────
  // 读操作 — 全量（同步引擎、标签统计等内部用途）
  // ────────────────────────────────────────────────────────────────

  /// 获取所有未删除、未归档的日记，按创建时间倒序。
  ///
  /// ⚠️ 此方法会返回全量数据，仅供同步引擎、内部统计等场景使用。
  /// UI 时间线展示请改用 [getMemosPaged]。
  static Future<List<MemoEntry>> getAllMemos() async {
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .sortByCreatedAtDesc()
        .findAll();
    debugPrint('[DB] getAllMemos → ${result.length} 条');
    return result;
  }

  /// 归档一条日记（标记 isArchived=true，syncStatus=pending）
  static Future<void> archiveMemo(int id) async {
    final isar = await db;
    final memo = await isar.memoEntrys.get(id);
    if (memo == null) return;
    await isar.writeTxn(() async {
      memo.isArchived = true;
      memo.syncStatus = SyncStatus.pending;
      memo.updatedAt = DateTime.now();
      await isar.memoEntrys.put(memo);
    });
    debugPrint('[DB] archiveMemo: id=$id');
  }

  /// 置顶（标记 isPinned=true，syncStatus=pending）
  static Future<void> pinMemo(int id) async {
    final isar = await db;
    final memo = await isar.memoEntrys.get(id);
    if (memo == null) return;
    await isar.writeTxn(() async {
      memo.isPinned = true;
      memo.syncStatus = SyncStatus.pending;
      memo.updatedAt = DateTime.now();
      await isar.memoEntrys.put(memo);
    });
    debugPrint('[DB] pinMemo: id=$id');
  }

  /// 取消置顶（标记 isPinned=false，syncStatus=pending）
  static Future<void> unpinMemo(int id) async {
    final isar = await db;
    final memo = await isar.memoEntrys.get(id);
    if (memo == null) return;
    await isar.writeTxn(() async {
      memo.isPinned = false;
      memo.syncStatus = SyncStatus.pending;
      memo.updatedAt = DateTime.now();
      await isar.memoEntrys.put(memo);
    });
    debugPrint('[DB] unpinMemo: id=$id');
  }

  /// 取消归档（标记 isArchived=false，syncStatus=pending）
  static Future<void> unarchiveMemo(int id) async {
    final isar = await db;
    final memo = await isar.memoEntrys.get(id);
    if (memo == null) return;
    await isar.writeTxn(() async {
      memo.isArchived = false;
      memo.syncStatus = SyncStatus.pending;
      memo.updatedAt = DateTime.now();
      await isar.memoEntrys.put(memo);
    });
    debugPrint('[DB] unarchiveMemo: id=$id');
  }

  /// 获取所有已归档的日记，按创建时间倒序（归档列表页使用）
  static Future<List<MemoEntry>> getArchivedMemos() async {
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(true)
        .sortByCreatedAtDesc()
        .findAll();
    debugPrint('[DB] getArchivedMemos → ${result.length} 条');
    return result;
  }

  // ────────────────────────────────────────────────────────────────
  // 读操作 — 分页（时间线 UI 使用）
  // ────────────────────────────────────────────────────────────────

  /// 获取所有置顶日记，按创建时间倒序。
  static Future<List<MemoEntry>> getPinnedMemos() async {
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .isPinnedEqualTo(true)
        .sortByCreatedAtDesc()
        .findAll();
    debugPrint('[DB] getPinnedMemos → ${result.length} 条');
    return result;
  }

  /// 获取所有冲突状态的日记（syncStatus == conflict），按创建时间倒序。
  static Future<List<MemoEntry>> getConflictMemos() async {
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .syncStatusEqualTo(SyncStatus.conflict)
        .sortByCreatedAtDesc()
        .findAll();
    debugPrint('[DB] getConflictMemos → ${result.length} 条');
    return result;
  }

  /// 分页获取未删除、未置顶日记，按创建时间倒序。
  static Future<List<MemoEntry>> getMemosPaged({
    int offset = 0,
    int limit = 50,
  }) async {
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .isPinnedEqualTo(false)
        .sortByCreatedAtDesc()
        .offset(offset)
        .limit(limit)
        .findAll();
    debugPrint('[DB] getMemosPaged offset=$offset limit=$limit → ${result.length} 条');
    return result;
  }

  /// 获取未删除、未置顶日记总条数（用于分页判断是否还有下一页）。
  static Future<int> getMemoCount() async {
    final isar = await db;
    final count = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .isPinnedEqualTo(false)
        .count();
    debugPrint('[DB] getMemoCount → $count 条');
    return count;
  }

  // ────────────────────────────────────────────────────────────────
  // 读操作 — 日历专用（按月/日精确查询）
  // ────────────────────────────────────────────────────────────────

  /// 获取指定月份中有日记的「天」集合（仅返回天数整数，不含完整日期）。
  ///
  /// 比 [getDatesWithMemos] 轻量得多：只查当月范围，返回简单的 int 集合。
  /// 日历渲染用此方法判断哪些格子需要高亮圆点。
  ///
  /// 示例：2025 年 12 月有日记的天 → `{7, 9, 10, 11}`
  static Future<Set<int>> getDaysWithMemoInMonth(int year, int month) async {
    final start = DateTime(year, month, 1);
    // month+1 会由 DateTime 自动处理跨年（如 12+1=13 → 次年 1 月）
    final end = DateTime(year, month + 1, 1);
    final isar = await db;
    final memos = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .createdAtBetween(start, end)
        .findAll();
    final days = memos.map((m) => m.createdAt.day).toSet();
    debugPrint('[DB] getDaysWithMemoInMonth $year-$month → 有记录天数：$days');
    return days;
  }

  /// 获取指定日期当天的所有未删除日记，按创建时间倒序。
  ///
  /// 日历点击某天后调用此方法加载当天详情列表。
  static Future<List<MemoEntry>> getMemosByDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .createdAtBetween(start, end)
        .sortByCreatedAtDesc()
        .findAll();
    debugPrint('[DB] getMemosByDate(${date.toLocal()}) → ${result.length} 条');
    return result;
  }

  // ────────────────────────────────────────────────────────────────
  // 读操作 — 其他
  // ────────────────────────────────────────────────────────────────

  /// 根据本地 id 获取单条日记（id 不存在时返回 null）。
  static Future<MemoEntry?> getMemoById(int id) async {
    final isar = await db;
    final memo = await isar.memoEntrys.get(id);
    debugPrint('[DB] getMemoById(id=$id) → ${memo == null ? "未找到" : "找到"}');
    return memo;
  }

  /// 根据远端资源名获取日记（如 "memos/42"）。
  static Future<MemoEntry?> getMemoByMemosName(String memosName) async {
    final isar = await db;
    return isar.memoEntrys
        .filter()
        .memosNameEqualTo(memosName)
        .findFirst();
  }

  /// 获取指定标签的所有未删除、未归档日记，按创建时间倒序。
  static Future<List<MemoEntry>> getMemosByTag(String tag) async {
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .tagsElementEqualTo(tag)
        .sortByCreatedAtDesc()
        .findAll();
    debugPrint('[DB] getMemosByTag(tag=$tag) → ${result.length} 条');
    return result;
  }

  /// 获取所有待同步（pending）的日记（含软删除条目）。
  static Future<List<MemoEntry>> getPendingSyncMemos() async {
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .syncStatusEqualTo(SyncStatus.pending)
        .findAll();
    debugPrint('[DB] getPendingSyncMemos → ${result.length} 条待同步');
    return result;
  }

  /// 全文搜索（在 content 中模糊匹配关键词），返回未删除、未归档的结果，按时间倒序。
  static Future<List<MemoEntry>> searchMemos(String query) async {
    if (query.trim().isEmpty) return [];
    final isar = await db;
    final all = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .findAll();
    final q = query.toLowerCase();
    final result = all
        .where((m) => m.content.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    debugPrint('[DB] searchMemos "$query" → ${result.length} 条');
    return result;
  }

  /// 归档日记全文搜索
  static Future<List<MemoEntry>> searchArchivedMemos(String query) async {
    if (query.trim().isEmpty) return [];
    final isar = await db;
    final all = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(true)
        .findAll();
    final q = query.toLowerCase();
    final result = all
        .where((m) => m.content.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    debugPrint('[DB] searchArchivedMemos "$query" → ${result.length} 条');
    return result;
  }

  /// 获取所有已同步（synced）且未删除的日记（用于检测远端删除）。
  static Future<List<MemoEntry>> getAllSyncedMemos() async {
    final isar = await db;
    final result = await isar.memoEntrys
        .filter()
        .syncStatusEqualTo(SyncStatus.synced)
        .isDeletedEqualTo(false)
        .findAll();
    return result;
  }

  /// 从本地 Isar 统计所有标签出现次数，返回 {tagName: count} 映射。
  ///
  /// 仅作离线降级使用，优先调用 [getCachedTagStats]。
  static Future<Map<String, int>> getAllTagCounts() async {
    final memos = await getAllMemos();
    final counts = <String, int>{};
    for (final memo in memos) {
      for (final tag in memo.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    debugPrint('[DB] getAllTagCounts（本地统计）→ ${counts.length} 个标签');
    return counts;
  }

  // ────────────────────────────────────────────────────────────────
  // 标签缓存（TagStat collection）
  // ────────────────────────────────────────────────────────────────

  /// 读取本地缓存的标签统计，按 count 倒序。
  ///
  /// 若缓存为空（首次启动/从未联网），返回空列表；
  /// 调用方应降级到 [getAllTagCounts]。
  static Future<List<TagStat>> getCachedTagStats() async {
    final isar = await db;
    final result = await isar.tagStats.where().findAll();
    result.sort((a, b) => b.count.compareTo(a.count));
    debugPrint('[DB] getCachedTagStats → ${result.length} 个标签');
    return result;
  }

  /// 将远端返回的 {tagName: count} 映射写入本地缓存（全量替换）。
  static Future<void> saveTagStats(Map<String, int> tagCounts) async {
    final isar = await db;
    final stats = tagCounts.entries
        .map((e) => TagStat.of(e.key, e.value))
        .toList();
    await isar.writeTxn(() async {
      await isar.tagStats.clear();
      await isar.tagStats.putAll(stats);
    });
    debugPrint('[DB] saveTagStats → 写入 ${stats.length} 个标签');
  }

  // ────────────────────────────────────────────────────────────────
  // 多标签筛选（支持分页）
  // ────────────────────────────────────────────────────────────────

  /// 按多个标签联合筛选（AND 语义），分页返回。
  ///
  /// [tags]：标签名列表（不含 '#'），所有标签都必须出现在日记中。
  /// [offset] / [limit]：分页参数。
  /// 返回条数小于 [limit] 表示已到最后一页。
  static Future<List<MemoEntry>> getMemosByTags({
    required List<String> tags,
    int offset = 0,
    int limit = 50,
  }) async {
    assert(tags.isNotEmpty);
    final isar = await db;

    // Isar 不支持多值索引的 AND 组合查询，先用第一个标签走索引缩小范围，
    // 再在 Dart 侧过滤其余标签，最后手动分页。
    final firstTag = tags.first;
    final candidates = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .isArchivedEqualTo(false)
        .tagsElementEqualTo(firstTag)
        .sortByCreatedAtDesc()
        .findAll();

    final remaining = tags.skip(1).toList();
    final filtered = remaining.isEmpty
        ? candidates
        : candidates
            .where((m) => remaining.every((t) => m.tags.contains(t)))
            .toList();

    final end = (offset + limit).clamp(0, filtered.length);
    final page = offset >= filtered.length ? <MemoEntry>[] : filtered.sublist(offset, end);
    debugPrint('[DB] getMemosByTags tags=$tags offset=$offset limit=$limit → ${page.length}/${filtered.length} 条');
    return page;
  }

  /// 获取有日记的日期集合（全量，供同步完成后刷新日历整体用）。
  ///
  /// 返回的 DateTime 已截断到天（时分秒为 0），方便日历比较。
  /// 日历月度渲染请改用更轻量的 [getDaysWithMemoInMonth]。
  static Future<Set<DateTime>> getDatesWithMemos() async {
    final memos = await getAllMemos();
    final dates = memos
        .map((m) =>
            DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day))
        .toSet();
    debugPrint('[DB] getDatesWithMemos → ${dates.length} 个有记录日期');
    return dates;
  }

  // ────────────────────────────────────────────────────────────────
  // 响应式 Stream
  // ────────────────────────────────────────────────────────────────

  /// 监听 DB 写操作事件，带 300ms debounce 节流。
  ///
  /// 原始 [watchLazy] 在批量写入（如同步 1000 条）时会连续触发数百次，
  /// debounce 保证最后一次写完后静默 300ms 才推送一次通知，
  /// 大幅减少高频重查带来的 CPU/内存开销。
  ///
  /// 返回的 Stream 只发出"有变化"的信号，不携带数据（由调用方决定查询策略）。
  static Future<Stream<void>> watchDbChanges() async {
    final isar = await db;
    debugPrint('[DB] 注册 watchDbChanges（含 debounce）');
    // fireImmediately: false —— 只监听后续写操作，首次加载由调用方主动触发
    // 合并 memoEntrys 和 commentEntrys，评论变化也能触发列表刷新
    final memoStream = isar.memoEntrys.watchLazy(fireImmediately: false);
    final commentStream = isar.commentEntrys.watchLazy(fireImmediately: false);
    return memoStream
        .mergeWith([commentStream])
        .debounceTime(const Duration(milliseconds: 300));
  }

  // ────────────────────────────────────────────────────────────────
  // 首次启动播种
  // ────────────────────────────────────────────────────────────────

  /// 若数据库为空，批量写入 [seeds] 作为演示数据。
  ///
  /// 仅在数据库中一条数据都没有时才写入，防止重复播种。
  static Future<void> seedIfEmpty(List<MemoEntry> seeds) async {
    final isar = await db;
    final count = await isar.memoEntrys.count();
    if (count > 0) {
      debugPrint('[DB] seedIfEmpty: 已有 $count 条数据，跳过播种');
      return;
    }
    debugPrint('[DB] seedIfEmpty: 数据库为空，写入 ${seeds.length} 条 Mock 数据');
    await isar.writeTxn(() async {
      for (final memo in seeds) {
        await isar.memoEntrys.put(memo);
      }
    });
    debugPrint('[DB] seedIfEmpty: 播种完成');
  }

  // ────────────────────────────────────────────────────────────────
  // 评论操作（CommentEntry collection）
  // ────────────────────────────────────────────────────────────────

  /// 新建或更新一条评论。
  /// [skipTimestamp] 为 true 时不修改 updatedAt（同步场景使用）。
  static Future<int> saveComment(CommentEntry comment,
      {bool skipTimestamp = false}) async {
    final isar = await db;
    if (!skipTimestamp) comment.updatedAt = DateTime.now();
    final id = await isar.writeTxn(() => isar.commentEntrys.put(comment));
    debugPrint('[DB] saveComment → id=$id memosName=${comment.memosName}');
    return id;
  }

  /// 获取指定日记（按 parentMemosName）的所有未删除评论，按创建时间升序。
  static Future<List<CommentEntry>> getCommentsByMemosName(
      String parentMemosName) async {
    final isar = await db;
    final result = await isar.commentEntrys
        .filter()
        .parentMemosNameEqualTo(parentMemosName)
        .isDeletedEqualTo(false)
        .sortByCreatedAt()
        .findAll();
    debugPrint('[DB] getCommentsByMemosName($parentMemosName) → ${result.length} 条');
    return result;
  }

  /// 获取指定日记（按本地 memoId）的所有未删除评论，用于离线新建评论的关联。
  static Future<List<CommentEntry>> getCommentsByMemoId(int memoId) async {
    final isar = await db;
    final result = await isar.commentEntrys
        .filter()
        .memoIdEqualTo(memoId)
        .isDeletedEqualTo(false)
        .sortByCreatedAt()
        .findAll();
    debugPrint('[DB] getCommentsByMemoId($memoId) → ${result.length} 条');
    return result;
  }

  /// 根据评论自身的远端资源名查找。
  static Future<CommentEntry?> getCommentByMemosName(String memosName) async {
    final isar = await db;
    return isar.commentEntrys
        .filter()
        .memosNameEqualTo(memosName)
        .findFirst();
  }

  /// 软删除评论。
  static Future<void> softDeleteComment(int id) async {
    final isar = await db;
    final comment = await isar.commentEntrys.get(id);
    if (comment == null) return;
    await isar.writeTxn(() async {
      comment.isDeleted = true;
      comment.syncStatus = SyncStatus.pending;
      comment.updatedAt = DateTime.now();
      await isar.commentEntrys.put(comment);
    });
    debugPrint('[DB] softDeleteComment: id=$id');
  }

  /// 物理删除评论（同步确认后调用）。
  static Future<void> hardDeleteComment(int id) async {
    final isar = await db;
    await isar.writeTxn(() => isar.commentEntrys.delete(id));
    debugPrint('[DB] hardDeleteComment: id=$id');
  }

  /// 获取所有待同步的评论（含软删除）。
  static Future<List<CommentEntry>> getPendingSyncComments() async {
    final isar = await db;
    final result = await isar.commentEntrys
        .filter()
        .syncStatusEqualTo(SyncStatus.pending)
        .findAll();
    debugPrint('[DB] getPendingSyncComments → ${result.length} 条');
    return result;
  }

  /// 全文搜索评论内容，返回未删除的匹配评论，按时间倒序。
  static Future<List<CommentEntry>> searchComments(String query) async {
    if (query.trim().isEmpty) return [];
    final isar = await db;
    final all = await isar.commentEntrys
        .filter()
        .isDeletedEqualTo(false)
        .findAll();
    final q = query.toLowerCase();
    final result = all
        .where((c) => c.content.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    debugPrint('[DB] searchComments "$query" → ${result.length} 条');
    return result;
  }

  // ────────────────────────────────────────────────────────────────
  // 清库
  // ────────────────────────────────────────────────────────────────

  /// 将所有未删除的日记和评论标记为 pending（待推送）。
  ///
  /// 保留 memosName：有 memosName 的条目 push 时走 updateMemo，
  /// 无 memosName 的走 createMemo，确保全量推送到远端。
  static Future<int> markAllPending() async {
    final isar = await db;

    // 日记：未删除的全部标记 pending
    final memos = await isar.memoEntrys
        .filter()
        .isDeletedEqualTo(false)
        .findAll();
    for (final memo in memos) {
      memo.syncStatus = SyncStatus.pending;
    }

    // 评论：未删除的全部标记 pending
    final comments = await isar.commentEntrys
        .filter()
        .isDeletedEqualTo(false)
        .findAll();
    for (final comment in comments) {
      comment.syncStatus = SyncStatus.pending;
    }

    await isar.writeTxn(() async {
      await isar.memoEntrys.putAll(memos);
      await isar.commentEntrys.putAll(comments);
    });

    final total = memos.length + comments.length;
    debugPrint('[DB] markAllPending: $total 条（日记 ${memos.length}，评论 ${comments.length}）');
    return total;
  }

  /// 清空所有本地数据（日记、评论、标签统计），不可恢复。
  ///
  /// 仅用于"清除本地缓存"功能，清空后需重新同步才能恢复数据。
  static Future<void> clearAll() async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.memoEntrys.clear();
      await isar.commentEntrys.clear();
      await isar.tagStats.clear();
    });
    debugPrint('[DB] clearAll: 所有数据已清空');
  }

  // ────────────────────────────────────────────────────────────────
  // 工具方法
  // ────────────────────────────────────────────────────────────────

  /// 从正文中提取 Memos 风格的标签（兼容 ASCII 和中文，支持 tag/subtag 嵌套格式）。
  ///
  /// 匹配规则：`#` 后跟至少一个非空白非 `#` 字符，且 `#` 前不能有非空白字符。
  ///
  /// 示例：`"今天 #想法 #work/project"` → `["想法", "work/project"]`
  static List<String> extractTags(String content) {
    // (?<!\S) 确保 # 前是行首或空白，防止 URL 中的 # 被误匹配
    final regex = RegExp(r'(?<!\S)#([^\s#]+)');
    final tags = regex
        .allMatches(content)
        .map((m) => m.group(1)!)
        .where((tag) => tag.isNotEmpty)
        .toList();
    if (tags.isNotEmpty) debugPrint('[DB] extractTags: $tags');
    return tags;
  }
}
