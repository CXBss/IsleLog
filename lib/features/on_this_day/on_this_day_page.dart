import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/memo_entry.dart';
import '../../shared/constants/app_constants.dart';
import '../home/widgets/memo_timeline_card.dart';

/// 往年今日页面
///
/// 展示历史上与当前日期相同月日的全部日记，按年份从新到旧分组。
/// 支持日期导航（前一天 / 后一天 / 日历选择）。
class OnThisDayPage extends StatefulWidget {
  const OnThisDayPage({super.key});

  @override
  State<OnThisDayPage> createState() => _OnThisDayPageState();
}

class _OnThisDayPageState extends State<OnThisDayPage> {
  late DateTime _date;
  List<MemoEntry> _memos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await DatabaseService.getMemosOnThisDay(_date);
    if (mounted) setState(() { _memos = result; _loading = false; });
  }

  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year && _date.month == now.month && _date.day == now.day;
  }

  void _goToDay(DateTime date) {
    setState(() { _date = date; });
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) _goToDay(picked);
  }

  /// 按年份倒序分组
  Map<int, List<MemoEntry>> get _groupedByYear {
    final map = <int, List<MemoEntry>>{};
    for (final m in _memos) {
      final yr = m.createdAt.year;
      (map[yr] ??= []).add(m);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isToday;
    return Scaffold(
      appBar: AppBar(
        title: const Text('往年今日', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (!isToday)
            TextButton(
              onPressed: () {
                final now = DateTime.now();
                _goToDay(DateTime(now.year, now.month, now.day));
              },
              child: const Text('今天',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          _DateNavBar(
            date: _date,
            onPrev: () => _goToDay(_date.subtract(const Duration(days: 1))),
            onNext: isToday ? null : () => _goToDay(_date.add(const Duration(days: 1))),
            onTap: _pickDate,
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_memos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_edu_outlined, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              '这一天还没有日记',
              style: TextStyle(fontSize: 15, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    final grouped = _groupedByYear;
    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: years.length,
      itemBuilder: (context, i) {
        final year = years[i];
        final memosInYear = grouped[year]!;
        return _YearSection(year: year, memos: memosInYear);
      },
    );
  }
}

// ── 日期导航栏 ────────────────────────────────────────────────────────────

class _DateNavBar extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onTap;

  const _DateNavBar({
    required this.date,
    required this.onPrev,
    required this.onNext,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = '${date.month}月${date.day}日';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
            tooltip: '前一天',
          ),
          GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: Colors.grey[500]),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                color: onNext == null ? Colors.grey[300] : null),
            onPressed: onNext,
            tooltip: '后一天',
          ),
        ],
      ),
    );
  }
}

// ── 年份分组区块 ──────────────────────────────────────────────────────────

class _YearSection extends StatelessWidget {
  final int year;
  final List<MemoEntry> memos;

  const _YearSection({required this.year, required this.memos});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$year 年',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        ...memos.map((memo) => MemoTimelineCard(memo: memo, showTime: true)),
        const SizedBox(height: 4),
      ],
    );
  }
}
