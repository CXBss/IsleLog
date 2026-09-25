import 'package:flutter/material.dart';

import '../../../services/ai/ai_models.dart';
import '../../../shared/constants/app_constants.dart';

/// 用户消息气泡（右对齐）。
class UserBubble extends StatelessWidget {
  final String text;

  const UserBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

/// 助手回复的底板。
class AssistantBubble extends StatelessWidget {
  final Widget child;

  const AssistantBubble({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// 记忆检索问答的结果：答案 + 可点击的来源日记。
///
/// 无依据不是错误：展示明确的空态，而不是让页面看起来像出错了。
class AnswerView extends StatelessWidget {
  final MemorySearchResult result;
  final void Function(String memoName) onOpenSource;

  const AnswerView({
    super.key,
    required this.result,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    if (result.insufficientEvidence) {
      return AssistantBubble(
        child: Row(
          children: [
            Icon(Icons.search_off, size: 16, color: Colors.grey[400]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '没有找到相关日记，换个问法试试？',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AssistantBubble(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.indexIncomplete)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '部分日记尚未完成索引，结果可能不全',
                    style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                  ),
                ),
              Text(result.answer, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
        if (result.sources.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: result.sources.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final source = result.sources[i];
                return SourceCard(
                  date: source.displayTime,
                  snippet: source.snippet,
                  onTap: () => onOpenSource(source.memo),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// 一篇来源日记的小卡片。
class SourceCard extends StatelessWidget {
  final DateTime? date;
  final String snippet;
  final VoidCallback? onTap;

  const SourceCard({
    super.key,
    required this.date,
    required this.snippet,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = date;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primaryLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d != null)
              Text(
                formatDate(d),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                snippet,
                style: const TextStyle(fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
