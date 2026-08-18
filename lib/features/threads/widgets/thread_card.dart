import 'package:flutter/material.dart';

import '../../../shared/constants/app_constants.dart';

/// 事件串卡片的展示数据，和持久化模型解耦以便复用。
class ThreadCardData {
  final String title;
  final String summary;
  final int memberCount;
  final DateTime? startedAt;
  final DateTime? lastAt;

  const ThreadCardData({
    required this.title,
    required this.summary,
    required this.memberCount,
    required this.startedAt,
    required this.lastAt,
  });
}

class ThreadCard extends StatelessWidget {
  final ThreadCardData data;
  final VoidCallback? onTap;

  const ThreadCard({super.key, required this.data, this.onTap});

  String _spanText() {
    if (data.startedAt == null || data.lastAt == null)
      return '${data.memberCount} 篇';
    String day(DateTime value) =>
        '${value.month.toString().padLeft(2, '0')}月${value.day.toString().padLeft(2, '0')}日';
    final start = day(data.startedAt!);
    final end = day(data.lastAt!);
    return '${data.memberCount} 篇 · ${start == end ? start : '$start–$end'}';
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppDimens.cardRadius),
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          if (data.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              data.summary,
              key: const Key('thread_card_summary'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _spanText(),
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    ),
  );
}
