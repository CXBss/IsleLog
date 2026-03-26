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

  final ScrollController _scrollCtrl = ScrollController();
  StreamSubscription<void>? _dbSub;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadNextPage();
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
    _dbSub = stream.listen((_) => _resetAndReload());
  }

  Future<void> _resetAndReload() async {
    if (!mounted) return;
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
    _loadingMore = true; // 不用 setState，避免触发多余重建
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

  void _onScroll() {
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

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
      ),
    );
  }

  void _openSearch() {
    showSearch(context: context, delegate: _MemoSearchDelegate());
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
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 1,
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
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _openMenu,
            tooltip: '菜单',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_memos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(AppStrings.homeEmpty,
                style: TextStyle(fontSize: 16, color: Colors.grey[400])),
            const SizedBox(height: 8),
            Text(AppStrings.homeEmptyHint,
                style: TextStyle(fontSize: 13, color: Colors.grey[350])),
          ],
        ),
      );
    }

    final groups = _groupByDay(_memos);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        // 根据可用宽度决定水平内边距：宽屏留更多空白
        final w = constraints.maxWidth;
        final hPad = w > 600 ? 24.0 : 12.0;
        // 底部 padding = BottomAppBar(56) + FAB溢出(~28) + 系统导航条
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
              itemCount: groups.length + (_hasMore ? 1 : 0),
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
                    dateKey: key, memos: dayMemos, weekdays: _weekdays);
              },
            ),
          ),
        );
      },
    );
  }
}

/// 单天时间线区块
///
/// 每条日记独立渲染为一个 Row，左侧日期列 + 右侧卡片。
/// Row 使用 crossAxisAlignment.start，不使用 IntrinsicHeight，
/// 轴线高度由 MemoTimelineCard 内部的 CustomPaint 自行处理。
class _DaySection extends StatelessWidget {
  final String dateKey;
  final List<MemoEntry> memos;
  final List<String> weekdays;

  const _DaySection({
    required this.dateKey,
    required this.memos,
    required this.weekdays,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(dateKey);
    final weekday = weekdays[date.weekday - 1];

    // 根据屏幕宽度缩放左侧日期列
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
                child: MemoTimelineCard(memo: memo, isLast: isLast),
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
