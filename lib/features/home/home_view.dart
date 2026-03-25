import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
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

  void _openSettings() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsPage()));
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

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: AppDimens.timelineMaxWidth),
        child: ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
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
                width: 60,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isFirst) ...[
                      const SizedBox(height: 18),
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
                    ] else
                      const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '$h:$m',
                        style: TextStyle(
                          fontSize: 11,
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
