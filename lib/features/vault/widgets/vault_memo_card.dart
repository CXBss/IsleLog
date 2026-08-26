import 'package:flutter/material.dart';

import '../../../data/models/memo_entry.dart';
import '../../../shared/constants/app_constants.dart';
import 'highlighted_text.dart';

/// 隐私空间里展示「主库普通日记」的卡片。
///
/// 与 [VaultEntryCard]（vault 条目）成对使用，靠图标和副标题区分来源。
/// 旧实现是个裸 ListTile，既不显示时间也不显示标签，无法判断该不该移入——
/// 这个卡片补上这些信息。
class VaultMemoCard extends StatelessWidget {
  final MemoEntry memo;

  /// 当前搜索词，用于正文高亮；无搜索时传空串
  final String query;

  final VoidCallback onLongPress;
  final VoidCallback? onTap;

  /// 与主页时间线卡片一致的行数截断（memo_timeline_card.dart 的 _kMaxLines）。
  static const int _kMaxLines = 6;

  const VaultMemoCard({
    super.key,
    required this.memo,
    required this.query,
    required this.onLongPress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface(context),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 16,
                    color: AppColors.textSecondary(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatTime(memo.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const Spacer(),
                  if (memo.attachmentsJson.isNotEmpty)
                    Icon(
                      Icons.attach_file,
                      size: 14,
                      color: AppColors.textSecondary(context),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              HighlightedText(
                text: memo.content,
                query: query,
                maxLines: _kMaxLines,
              ),
              if (memo.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: memo.tags
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#$t',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
