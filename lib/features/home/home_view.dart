import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../features/settings/settings_page.dart';
import '../../services/sync/sync_service.dart';
import 'widgets/memo_timeline_card.dart';

/// 时间线主页（从本地 DB 实时读取，按天分组倒序展示）
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  Stream<List<MemoEntry>>? _stream;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  Future<void> _initStream() async {
    final stream = await DatabaseService.watchAllMemos();
    if (mounted) setState(() => _stream = stream);
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final result = await SyncService.syncAll();
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.toString()),
          backgroundColor: result.success ? null : Colors.red,
        ),
      );
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          '时间线',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          // 同步按钮（同步中显示 loading）
          _syncing
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF4CAF50)),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: _syncNow,
                  tooltip: '立即同步',
                ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
            tooltip: '设置',
          ),
        ],
      ),
      body: StreamBuilder<List<MemoEntry>>(
        stream: _stream,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(child: Text('加载失败：${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
            );
          }

          final memos = snap.data!;
          if (memos.isEmpty) return _buildEmptyState(context);

          final groups = _groupByDay(memos);
          final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: sortedKeys.length,
            itemBuilder: (ctx, i) {
              final key = sortedKeys[i];
              final dayMemos = groups[key]!
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              return _DaySection(dateKey: key, memos: dayMemos, weekdays: _weekdays);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.book_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('还没有日记', style: TextStyle(fontSize: 16, color: Colors.grey[400])),
          const SizedBox(height: 8),
          Text(
            '点击下方 + 开始记录',
            style: TextStyle(fontSize: 13, color: Colors.grey[350]),
          ),
        ],
      ),
    );
  }
}

/// 单天的时间线区块
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 左侧日期列 ──────────────────────────────────────
          SizedBox(
            width: 60,
            child: Padding(
              padding: const EdgeInsets.only(top: 18, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${date.day}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  Text('${date.month}月',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 2),
                  Text('星期$weekday',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                ],
              ),
            ),
          ),

          // ── 右侧时间线条目 ──────────────────────────────────
          Expanded(
            child: Column(
              children: memos.asMap().entries.map((e) {
                return MemoTimelineCard(
                  memo: e.value,
                  isLast: e.key == memos.length - 1,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
