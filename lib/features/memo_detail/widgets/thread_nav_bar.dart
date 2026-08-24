import 'package:flutter/material.dart';
import '../../../shared/constants/app_constants.dart';

/// 日记在某条事件串内的位置。
class ThreadNavData {
  final String threadTitle;
  final int position;
  final int total;
  final bool hasPrevious;
  final bool hasNext;
  const ThreadNavData({
    required this.threadTitle,
    required this.position,
    required this.total,
    required this.hasPrevious,
    required this.hasNext,
  });
}

/// 让用户在日记详情页直接阅读事件的前后文。
class ThreadNavBar extends StatelessWidget {
  final ThreadNavData data;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onOpenThread;
  const ThreadNavBar({
    super.key,
    required this.data,
    this.onPrevious,
    this.onNext,
    this.onOpenThread,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.primarySofter(context),
      border: Border(top: BorderSide(color: AppColors.subtleBorder(context))),
    ),
    child: Row(
      children: [
        IconButton(
          key: const Key('thread_nav_previous'),
          icon: const Icon(Icons.chevron_left),
          tooltip: '上一篇',
          onPressed: data.hasPrevious ? onPrevious : null,
        ),
        Expanded(
          child: InkWell(
            key: const Key('thread_nav_title'),
            onTap: onOpenThread,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '「${data.threadTitle}」${data.position}/${data.total}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.onPrimarySoft(context),
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('thread_nav_next'),
          icon: const Icon(Icons.chevron_right),
          tooltip: '下一篇',
          onPressed: data.hasNext ? onNext : null,
        ),
      ],
    ),
  );
}
