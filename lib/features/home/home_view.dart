import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../data/models/tag_stat.dart';
import '../../features/archive/archive_view.dart';
import '../../features/settings/settings_page.dart';
import '../../services/api/memos_api_service.dart';
import '../../services/settings/settings_service.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';
import 'widgets/memo_search_card.dart';
import 'widgets/memo_timeline_card.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const _pageSize = 50;

  // ── 普通分页模式 ───────────────────────────────────────────────
  final List<MemoEntry> _memos = [];
  int _offset = 0;
  bool _hasMore = true;

  // ── 标签筛选分页模式 ───────────────────────────────────────────
  final List<MemoEntry> _tagFilteredMemos = [];
  int _tagOffset = 0;
  bool _tagHasMore = true;

  // ── 状态 ──────────────────────────────────────────────────────
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _syncing = false;

  /// 当前已选中的标签集合（空 = 不过滤）
  final Set<String> _selectedTags = {};

  /// 所有标签及其计数（Drawer 中展示）
  List<TagStat> _tagStats = [];

  final ScrollController _scrollCtrl = ScrollController();
  StreamSubscription<void>? _dbSub;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadNextPage();
    _loadTagStats();
    _initDbWatch();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _dbSub?.cancel();
    super.dispose();
  }

  Future<void> _initDbWatch() async {
    final stream = await DatabaseService.watchDbChanges();
    _dbSub = stream.listen((_) {
      _resetAndReload();
      _loadTagStats();
    });
  }

  // ── 标签统计 ──────────────────────────────────────────────────

  /// 优先从 API 获取标签统计，失败时降级到本地缓存，缓存也空则本地统计
  Future<void> _loadTagStats() async {
    // 1. 先用本地缓存快速显示
    final cached = await DatabaseService.getCachedTagStats();
    if (cached.isNotEmpty && mounted) {
      setState(() => _tagStats = cached);
    }

    // 2. 尝试从 API 刷新
    try {
      final url = await SettingsService.serverUrl;
      final token = await SettingsService.accessToken;
      if (url == null || url.isEmpty || token == null || token.isEmpty) {
        throw Exception('未配置服务器');
      }
      final api = MemosApiService(baseUrl: url, token: token);
      // 先获取当前用户 name
      final user = await api.testConnection();
      final userName = user['name'] as String?;
      if (userName == null || userName.isEmpty) throw Exception('无法获取用户名');

      final stats = await api.getUserStats(userName);
      final rawTagCount = stats['tagCount'];
      if (rawTagCount is Map) {
        final tagCounts = rawTagCount.map(
            (k, v) => MapEntry(k as String, (v as num).toInt()));
        await DatabaseService.saveTagStats(tagCounts);
        final updated = await DatabaseService.getCachedTagStats();
        if (mounted) setState(() => _tagStats = updated);
      }
    } catch (e) {
      debugPrint('[HomeView] 标签统计 API 失败，使用本地数据：$e');
      // 若本地缓存也是空，则本地统计一次
      if (_tagStats.isEmpty) {
        final counts = await DatabaseService.getAllTagCounts();
        if (counts.isNotEmpty) {
          await DatabaseService.saveTagStats(counts);
          final fallback = await DatabaseService.getCachedTagStats();
          if (mounted) setState(() => _tagStats = fallback);
        }
      }
    }
  }

  // ── 数据加载 ──────────────────────────────────────────────────

  Future<void> _resetAndReload() async {
    if (!mounted) return;
    if (_selectedTags.isNotEmpty) {
      setState(() {
        _tagFilteredMemos.clear();
        _tagOffset = 0;
        _tagHasMore = true;
        _initialLoading = true;
      });
      await _loadTagFiltered();
      return;
    }
    setState(() {
      _memos.clear();
      _offset = 0;
      _hasMore = true;
      _initialLoading = true;
    });
    await _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    final page = await DatabaseService.getMemosPaged(
        offset: _offset, limit: _pageSize);
    if (mounted) {
      setState(() {
        _memos.addAll(page);
        _offset += page.length;
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
        _initialLoading = false;
      });
    } else {
      _loadingMore = false;
    }
  }

  Future<void> _loadTagFiltered() async {
    if (_loadingMore || !_tagHasMore) return;
    _loadingMore = true;
    final page = await DatabaseService.getMemosByTags(
      tags: _selectedTags.toList(),
      offset: _tagOffset,
      limit: _pageSize,
    );
    if (mounted) {
      setState(() {
        _tagFilteredMemos.addAll(page);
        _tagOffset += page.length;
        _tagHasMore = page.length == _pageSize;
        _loadingMore = false;
        _initialLoading = false;
      });
    } else {
      _loadingMore = false;
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels <
        _scrollCtrl.position.maxScrollExtent - 200) return;
    if (_selectedTags.isNotEmpty) {
      _loadTagFiltered();
    } else {
      _loadNextPage();
    }
  }

  // ── 标签选择 ──────────────────────────────────────────────────

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
      _tagFilteredMemos.clear();
      _tagOffset = 0;
      _tagHasMore = true;
      _initialLoading = true;
    });
    if (_selectedTags.isNotEmpty) {
      _loadTagFiltered();
    } else {
      // 恢复普通分页
      setState(() {
        _memos.clear();
        _offset = 0;
        _hasMore = true;
      });
      _loadNextPage();
    }
  }

  void _clearTags() {
    if (_selectedTags.isEmpty) return;
    setState(() {
      _selectedTags.clear();
      _tagFilteredMemos.clear();
      _tagOffset = 0;
      _tagHasMore = true;
      _memos.clear();
      _offset = 0;
      _hasMore = true;
      _initialLoading = true;
    });
    _loadNextPage();
  }

  // ── 同步 ──────────────────────────────────────────────────────

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final result = await SyncService.syncAll();
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.toString()),
        backgroundColor: result.success ? null : AppColors.error,
      ));
    }
  }

  Future<void> _syncFull() async {
    if (_syncing) return;
    Navigator.pop(context);
    setState(() => _syncing = true);
    final result = await SyncService.syncFull();
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.toString()),
        backgroundColor: result.success ? null : AppColors.error,
      ));
    }
  }

  void _openSearch() {
    showSearch(context: context, delegate: _MemoSearchDelegate());
  }

  // ── 分组 ──────────────────────────────────────────────────────

  List<(String, List<MemoEntry>)> _groupByDay(List<MemoEntry> memos) {
    final map = <String, List<MemoEntry>>{};
    for (final m in memos) {
      final k =
          '${m.createdAt.year}-${m.createdAt.month.toString().padLeft(2, '0')}-'
          '${m.createdAt.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(k, () => []).add(m);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.map((k) {
      final dayMemos = map[k]!
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return (k, dayMemos);
    }).toList();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.scaffoldBg,
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: '菜单',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(AppStrings.homeTitle,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          _syncing
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: _syncNow,
                  tooltip: AppStrings.homeSyncTooltip,
                ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
            tooltip: '搜索',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  // ── 抽屉 ──────────────────────────────────────────────────────

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                '日记本',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('服务器设置'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('归档日记'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ArchiveView()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('全量同步'),
              subtitle: const Text('拉取全部数据并检测远端删除',
                  style: TextStyle(fontSize: 12)),
              onTap: _syncing ? null : _syncFull,
            ),
            const Divider(height: 1),
            // ── 标签区标题 ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '标签',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[500],
                    ),
                  ),
                  if (_selectedTags.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: AppColors.primary,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _clearTags();
                      },
                      child: const Text('清除筛选', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            // ── 标签列表 ────────────────────────────────────────
            Expanded(
              child: _tagStats.isEmpty
                  ? Center(
                      child: Text('还没有标签',
                          style: TextStyle(
                              color: Colors.grey[400], fontSize: 13)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _tagStats.length,
                      itemBuilder: (ctx, i) {
                        final stat = _tagStats[i];
                        final isSelected = _selectedTags.contains(stat.name);
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.label_outline,
                            size: 18,
                            color: isSelected
                                ? AppColors.primary
                                : Colors.grey[500],
                          ),
                          title: Text(
                            '#${stat.name}',
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primaryLight
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${stat.count}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? AppColors.primaryDark
                                    : Colors.grey[500],
                              ),
                            ),
                          ),
                          selected: isSelected,
                          selectedTileColor: AppColors.primaryLighter,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          onTap: () {
                            Navigator.pop(context);
                            _toggleTag(stat.name);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 主体内容 ──────────────────────────────────────────────────

  Widget _buildBody() {
    final isFiltering = _selectedTags.isNotEmpty;

    return Column(
      children: [
        // ── 已选标签 chips（筛选时显示）───────────────────────
        if (isFiltering) _buildSelectedTagsBar(),

        // ── 列表主体 ──────────────────────────────────────────
        Expanded(child: _buildList()),
      ],
    );
  }

  /// 顶部已选标签条，每个 chip 右侧有 × 可单独移除
  Widget _buildSelectedTagsBar() {
    return Container(
      color: AppColors.surfaceWhite,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _selectedTags.map((tag) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _SelectedTagChip(
                      tag: tag,
                      onRemove: () => _toggleTag(tag),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // 全部清除按钮
          GestureDetector(
            onTap: _clearTags,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_initialLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    final isFiltering = _selectedTags.isNotEmpty;
    final memos = isFiltering ? _tagFilteredMemos : _memos;
    final hasMore = isFiltering ? _tagHasMore : _hasMore;

    if (memos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              isFiltering ? '该标签组合下没有日记' : AppStrings.homeEmpty,
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
            ),
            if (!isFiltering) ...[
              const SizedBox(height: 8),
              Text(AppStrings.homeEmptyHint,
                  style: TextStyle(fontSize: 13, color: Colors.grey[350])),
            ],
          ],
        ),
      );
    }

    final groups = _groupByDay(memos);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final hPad = w > 600 ? 24.0 : 12.0;
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final bottomPad = 84.0 + bottomInset;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppDimens.timelineMaxWidth),
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: EdgeInsets.fromLTRB(hPad, 12, hPad, bottomPad),
              itemCount: groups.length + (hasMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == groups.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  );
                }
                final (key, dayMemos) = groups[i];
                return _DaySection(
                  dateKey: key,
                  memos: dayMemos,
                  weekdays: _weekdays,
                  onTagTap: _toggleTag,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// ── 已选标签 Chip ──────────────────────────────────────────────────

class _SelectedTagChip extends StatelessWidget {
  final String tag;
  final VoidCallback onRemove;
  const _SelectedTagChip({required this.tag, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$tag',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 14, color: AppColors.primaryDark),
          ),
        ],
      ),
    );
  }
}

/// 单天时间线区块
class _DaySection extends StatelessWidget {
  final String dateKey;
  final List<MemoEntry> memos;
  final List<String> weekdays;
  final void Function(String tag) onTagTap;

  const _DaySection({
    required this.dateKey,
    required this.memos,
    required this.weekdays,
    required this.onTagTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(dateKey);
    final weekday = weekdays[date.weekday - 1];

    final screenW = MediaQuery.sizeOf(context).width;
    final isNarrow = screenW < 360;
    final dateColWidth = isNarrow ? 52.0 : 60.0;
    final dayFontSize = isNarrow ? 24.0 : 30.0;
    final monthFontSize = isNarrow ? 11.0 : 12.0;
    final weekFontSize = isNarrow ? 10.0 : 11.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: memos.asMap().entries.map((e) {
          final isFirst = e.key == 0;
          final isLast = e.key == memos.length - 1;
          final memo = e.value;
          final h = memo.createdAt.hour.toString().padLeft(2, '0');
          final m = memo.createdAt.minute.toString().padLeft(2, '0');

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: dateColWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isFirst) ...[
                      const SizedBox(height: 18),
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: dayFontSize,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text('${date.month}月',
                          style: TextStyle(
                              fontSize: monthFontSize,
                              color: Colors.grey[600])),
                      const SizedBox(height: 2),
                      Text('星期$weekday',
                          style: TextStyle(
                              fontSize: weekFontSize,
                              color: Colors.grey[400])),
                      const SizedBox(height: 4),
                    ] else
                      const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '$h:$m',
                        style: TextStyle(
                          fontSize: isNarrow ? 10.0 : 11.0,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: MemoTimelineCard(
                  memo: memo,
                  isLast: isLast,
                  onTagTap: onTagTap,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── 搜索 ──────────────────────────────────────────────────────────

class _MemoSearchDelegate extends SearchDelegate<void> {
  @override
  String get searchFieldLabel => '搜索日记内容…';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _SearchResults(query: query);

  @override
  Widget buildSuggestions(BuildContext context) =>
      query.isEmpty ? const SizedBox() : _SearchResults(query: query);
}

class _SearchResults extends StatefulWidget {
  final String query;
  const _SearchResults({required this.query});

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  List<MemoEntry> _results = [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _doSearch(widget.query);
  }

  @override
  void didUpdateWidget(_SearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _doSearch(widget.query);
  }

  Future<void> _doSearch(String q) async {
    if (q == _lastQuery) return;
    _lastQuery = q;
    setState(() => _loading = true);
    final results = await DatabaseService.searchMemos(q);
    if (mounted && _lastQuery == q) {
      setState(() {
        _results = results;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_results.isEmpty) {
      return Center(
        child: Text('没有找到"${widget.query}"',
            style: const TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _results.length,
      itemBuilder: (ctx, i) => MemoSearchCard(
        key: ValueKey(_results[i].id),
        memo: _results[i],
        query: widget.query,
      ),
    );
  }
}
