import 'package:flutter/material.dart';

import '../../../shared/constants/app_constants.dart';

/// 4 格概览卡片：总字数、记录天数、日均字数、单日最高
class StatsOverviewCard extends StatelessWidget {
  final int totalWords;
  final int recordDays;
  final int avgDayWords;
  final int maxDayWords;

  const StatsOverviewCard({
    super.key,
    required this.totalWords,
    required this.recordDays,
    required this.avgDayWords,
    required this.maxDayWords,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.0,
      children: [
        _StatCell(label: '总字数', value: _fmt(totalWords), unit: '字'),
        _StatCell(label: '记录天数', value: '$recordDays', unit: '天'),
        _StatCell(label: '日均字数', value: _fmt(avgDayWords), unit: '字'),
        _StatCell(label: '单日最高', value: _fmt(maxDayWords), unit: '字'),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    if (n >= 1000) {
      // 用千分位：1,234
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

  const _StatCell({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
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
