import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../features/settings/settings_page.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';
import 'widgets/memo_timeline_card.dart';

/// 时间线主页
///
/// ## 性能策略
///
/// 不再全量加载所有日记，改为**无限滚动分页**：
///
/// 1. 初始加载第 1 页（50 条），渲染后立即可交互。
/// 2. 用户滚动到接近底部时，自动追加下一页数据（上拉加载）。
/// 3. DB 变更通知（带 300ms debounce）到达时，重置到第 1 页重新加载，
///    保证新建/编辑/同步后时间线立即更新且不全量重查。
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const _pageSize = 50;

  // ── 分页状态 ──────────────────────────────────────────────────

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
    _initDbWatch();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _dbSub?.cancel();
    super.dispose();
  }

  // ── DB 监听 ───────────────────────────────────────────────────

  Future<void> _initDbWatch() async {
    debugPrint('[HomeView] 初始化 DB 监听...');
    final stream = await DatabaseService.watchDbChanges();
    _dbSub = stream.listen((_) {
      debugPrint('[HomeView] DB 变更，重置并重新加载首页');
      _resetAndReload();
    });
  }

  // ── 分页加载 ──────────────────────────────────────────────────

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
    debugPrint('[HomeView] 加载分页 offset=$_offset limit=$_pageSize');
    setState(() => _loadingMore = true);

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
      debugPrint(
          '[HomeView] 加载完成，共 ${_memos.length} 条，hasMore=$_hasMore');
    }
  }

  // ── 滚动监听 ──────────────────────────────────────────────────

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  // ── 同步 ──────────────────────────────────────────────────────

  Future<void> _syncNow() async {
    if (_syncing) return;
    debugPrint('[HomeView] 开始手动同步...');
    setState(() => _syncing = true);
    final result = await SyncService.syncAll();
    debugPrint('[HomeView] 同步完成：$result');
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.toString()),
          backgroundColor: result.success ? null : AppColors.error,
        ),
      );
    }
  }

  void _openSettings() {
    debugPrint('[HomeView] 打开设置页');
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  // ── 数据处理 ──────────────────────────────────────────────────

  Map<String, List<MemoEntry>> _groupByDay(List<MemoEntry> memos) {
    final groups = <String, List<MemoEntry>>{};
    for (final m in memos) {
      final k =
          '${m.createdAt.year}-${m.createdAt.month.toString().padLeft(2, '0')}-'
          '${m.createdAt.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(k, () => []).add(m);
    }
    return groups;
  }

  // ── 构建 ──────────────────────────────────────────────────────

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
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: AppStrings.homeSettingsTooltip,
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
    if (_memos.isEmpty) return _buildEmptyState();

    final groups = _groupByDay(_memos);
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: AppDimens.timelineMaxWidth),
        child: ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: sortedKeys.length + (_hasMore ? 1 : 0),
          itemBuilder: (ctx, i) {
            // 末尾 loading 指示器
            if (i == sortedKeys.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              );
            }
            final key = sortedKeys[i];
            final dayMemos = groups[key]!
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return _DaySection(
                dateKey: key, memos: dayMemos, weekdays: _weekdays);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
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
}

/// 单天的时间线区块（排版与原版完全一致）
///
/// 左侧：第一条显示大号日期 + 月份 + 星期，后续条目只显示时间。
/// 右侧：[MemoTimelineCard] 卡片列表。
///
/// 注意：[MemoTimelineCard] 内部已改用 CustomPaint 绘制轴线，
/// 不再依赖 IntrinsicHeight，此处嵌套 Column 不会引发 layout 竞态。
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

    String fmtTime(DateTime dt) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: memos.asMap().entries.map((e) {
          final isFirst = e.key == 0;
          final memo = e.value;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 左侧日期 / 时间列 ──────────────────────────────
              SizedBox(
                width: 60,
                child: Padding(
                  padding: EdgeInsets.only(
                      top: isFirst ? 18 : 12, right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isFirst) ...[
                        Text(
                          '${date.day}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text('${date.month}月',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                        const SizedBox(height: 2),
                        Text('星期$weekday',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[400])),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        fmtTime(memo.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── 右侧时间线卡片 ─────────────────────────────────
              Expanded(
                child: MemoTimelineCard(
                  memo: memo,
                  isLast: e.key == memos.length - 1,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
