import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../features/archive/archive_view.dart';
import '../../features/settings/settings_page.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';
import 'widgets/memo_timeline_card.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const _pageSize = 50;

  final List<MemoEntry> _memos = [];
  int _offset = 0;
  bool _hasMore = true;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _syncing = false;

  /// 当前筛选标签（null = 不过滤，显示全部）
  String? _selectedTag;

  /// 按标签筛选时的结果列表（_selectedTag != null 时使用）
  List<MemoEntry> _tagFilteredMemos = [];

  /// 所有标签及其计数（Drawer 中展示）
  Map<String, int> _tagCounts = {};

  final ScrollController _scrollCtrl = ScrollController();
  StreamSubscription<void>? _dbSub;

  // ── GlobalKey for Drawer ──────────────────────────────────────
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadNextPage();
    _loadTagCounts();
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
      _loadTagCounts();
    });
  }

  Future<void> _loadTagCounts() async {
    final counts = await DatabaseService.getAllTagCounts();
    if (mounted) setState(() => _tagCounts = counts);
  }

  Future<void> _resetAndReload() async {
    if (!mounted) return;
    if (_selectedTag != null) {
      await _loadTagFiltered(_selectedTag!);
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

  Future<void> _loadTagFiltered(String tag) async {
    if (!mounted) return;
    setState(() => _initialLoading = true);
    final results = await DatabaseService.getMemosByTag(tag);
    if (mounted) {
      setState(() {
        _tagFilteredMemos = results;
        _initialLoading = false;
      });
    }
  }

  void _onScroll() {
    if (_selectedTag != null) return; // 标签筛选模式不需要分页
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

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
    Navigator.pop(context); // 关闭 Drawer
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

  /// 选择标签筛选（传 null 表示清除筛选）
  void _selectTag(String? tag) {
    if (_selectedTag == tag) return;
    setState(() {
      _selectedTag = tag;
      _tagFilteredMemos = [];
      _initialLoading = true;
    });
    if (tag == null) {
      // 恢复分页模式
      setState(() {
        _memos.clear();
        _offset = 0;
        _hasMore = true;
      });
      _loadNextPage();
    } else {
      _loadTagFiltered(tag);
    }
  }

  /// 将日记列表按天分组，返回按日期倒序排列的 (dateKey, memos) 列表
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
      final dayMemos = map[k]!..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return (k, dayMemos);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.scaffoldBg,
      // ── 左侧抽屉 ──────────────────────────────────────────────
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
        title: _selectedTag != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.label_outline,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('#$_selectedTag',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                ],
              )
            : const Text(AppStrings.homeTitle,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (_selectedTag != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '清除筛选',
              onPressed: () => _selectTag(null),
            ),
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

  // ── 抽屉 ───────────────────────────────────────────────────────

  Widget _buildDrawer() {
    // 按出现次数倒序排列标签
    final sortedTags = _tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 应用标题区 ────────────────────────────────────
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

            // ── 菜单项 ────────────────────────────────────────
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

            // ── 标签区标题 ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
                  if (_selectedTag != null)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _selectTag(null);
                      },
                      child: Text(
                        '清除筛选',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── 标签列表 ──────────────────────────────────────
            Expanded(
              child: sortedTags.isEmpty
                  ? Center(
                      child: Text(
                        '还没有标签',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: sortedTags.length,
                      itemBuilder: (ctx, i) {
                        final tag = sortedTags[i].key;
                        final count = sortedTags[i].value;
                        final isSelected = _selectedTag == tag;
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
                            '#$tag',
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
                              '$count',
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
                            _selectTag(isSelected ? null : tag);
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

  // ── 主体内容 ───────────────────────────────────────────────────

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    final memos = _selectedTag != null ? _tagFilteredMemos : _memos;

    if (memos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _selectedTag != null ? '该标签下没有日记' : AppStrings.homeEmpty,
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
            ),
            if (_selectedTag == null) ...[
              const SizedBox(height: 8),
              Text(AppStrings.homeEmptyHint,
                  style: TextStyle(fontSize: 13, color: Colors.grey[350])),
            ],
          ],
        ),
      );
    }

    final groups = _groupByDay(memos);
    final hasMore = _selectedTag == null && _hasMore;

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
                    onTagTap: (tag) => _selectTag(tag));
              },
            ),
          ),
        );
      },
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
              // ── 左侧：日期头（仅第一条）+ 时间 ────────────────
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

              // ── 右侧：时间轴 + 卡片 ───────────────────────────
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

// ── 搜索 ───────────────────────────────────────────────────────────

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
      setState(() { _results = results; _loading = false; });
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
      itemBuilder: (ctx, i) => MemoTimelineCard(
        key: ValueKey(_results[i].id),
        memo: _results[i],
        isLast: i == _results.length - 1,
        showTime: true,
      ),
    );
  }
}
