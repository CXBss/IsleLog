import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../shared/constants/app_constants.dart';
import 'widgets/bar_chart_widget.dart';
import 'widgets/heatmap_widget.dart';
import 'widgets/stats_overview_card.dart';

/// 字数统计页
///
/// 包含：4 格概览、热力图（近365天）、月度柱状图、年度柱状图。
/// 通过 HomeView Drawer 入口进入，使用 Navigator.push 跳转。
class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  StatsData? _data;
  bool _loading = true;

  /// 月度图显示的年份（默认当年，可切换）
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DatabaseService.getStatsData();
    if (mounted) {
      setState(() {
        _data = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('字数统计',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _data == null
              ? const Center(child: Text('暂无数据'))
              : _buildContent(_data!),
    );
  }

  Widget _buildContent(StatsData data) {
    final now = DateTime.now();
    final years = data.yearlyWords().keys.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // ── 概览 ──────────────────────────────────────────────────
        StatsOverviewCard(
          totalWords: data.totalWords,
          recordDays: data.recordDays,
          avgDayWords: data.avgDayWords,
          maxDayWords: data.maxDayWords,
        ),
        const SizedBox(height: 20),

        // ── 热力图 ────────────────────────────────────────────────
        _SectionTitle(title: '近 365 天字数'),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: HeatmapWidget(
              dailyWords: data.dailyWords,
              onDayTap: (date) {
                final words = data.dailyWords[date] ?? 0;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${date.month}月${date.day}日  $words 字'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── 月度柱状图 ────────────────────────────────────────────
        Row(
          children: [
            Expanded(child: _SectionTitle(title: '$_selectedYear 年各月字数')),
            if (years.length > 1) ...[
              _YearStepper(
                year: _selectedYear,
                minYear: years.first,
                maxYear: years.last,
                onChanged: (y) => setState(() => _selectedYear = y),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        BarChartWidget(
          labels: const [
            '1月', '2月', '3月', '4月', '5月', '6月',
            '7月', '8月', '9月', '10月', '11月', '12月'
          ],
          values: data.monthlyWords(_selectedYear),
          highlightIndex: _selectedYear == now.year ? now.month - 1 : null,
          height: 150,
        ),
        const SizedBox(height: 24),

        // ── 年度柱状图 ────────────────────────────────────────────
        if (years.isNotEmpty) ...[
          _SectionTitle(title: '历年字数'),
          const SizedBox(height: 8),
          BarChartWidget(
            labels: years.map((y) => '$y').toList(),
            values: data.yearlyWords().values.toList(),
            highlightIndex: years.indexOf(now.year),
            height: 150,
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.primaryDark,
      ),
    );
  }
}

/// 年份切换控件（← 年份 →）
class _YearStepper extends StatelessWidget {
  final int year;
  final int minYear;
  final int maxYear;
  final ValueChanged<int> onChanged;

  const _YearStepper({
    required this.year,
    required this.minYear,
    required this.maxYear,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: year > minYear ? () => onChanged(year - 1) : null,
          color: AppColors.primary,
        ),
        SizedBox(
          width: 38,
          child: Text(
            '$year',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: year < maxYear ? () => onChanged(year + 1) : null,
          color: AppColors.primary,
        ),
      ],
    );
  }
}
