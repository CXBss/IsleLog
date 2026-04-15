import 'package:flutter/material.dart';

import '../../../shared/constants/app_constants.dart';

/// 6 格概览卡片：4 格日记统计 + 2 格文章统计
class StatsOverviewCard extends StatelessWidget {
  final int totalWords;
  final int recordDays;
  final int avgDayWords;
  final int maxDayWords;
  final int articleCount;
  final int articleTotalWords;

  const StatsOverviewCard({
    super.key,
    required this.totalWords,
    required this.recordDays,
    required this.avgDayWords,
    required this.maxDayWords,
    required this.articleCount,
    required this.articleTotalWords,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日记统计 4 格
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.0,
          children: [
            _StatCell(label: '日记总字数', value: _fmt(totalWords), unit: '字'),
            _StatCell(label: '记录天数', value: '$recordDays', unit: '天'),
            _StatCell(label: '日均字数', value: _fmt(avgDayWords), unit: '字'),
            _StatCell(label: '单日最高', value: _fmt(maxDayWords), unit: '字'),
          ],
        ),
        const SizedBox(height: 10),
        // 文章统计 2 格（同行排列，与日记格等宽）
        Row(
          children: [
            Expanded(
              child: _StatCell(
                label: '文章篇数',
                value: '$articleCount',
                unit: '篇',
                accent: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCell(
                label: '文章总字数',
                value: _fmt(articleTotalWords),
                unit: '字',
                accent: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    if (n >= 1000) {
      final s = n.toString();
      final buf = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    return '$n';
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  /// 文章统计格用稍深底色区分
  final bool accent;

  const _StatCell({
    required this.label,
    required this.value,
    required this.unit,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent ? AppColors.primaryLight.withAlpha(200) : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        border: accent
            ? Border.all(color: AppColors.primary.withAlpha(60), width: 1)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                unit,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
