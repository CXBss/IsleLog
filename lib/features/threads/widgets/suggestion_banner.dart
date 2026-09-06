import 'package:flutter/material.dart';

import '../../../shared/constants/app_constants.dart';

/// 横幅中一条待确认建议的展示数据
class SuggestionItem {
  final String suggestionLocalKey;
  final String memoSnippet;
  final String threadTitle;
  final String reason;

  const SuggestionItem({
    required this.suggestionLocalKey,
    required this.memoSnippet,
    required this.threadTitle,
    required this.reason,
  });
}

/// 事件串页顶部的待确认建议横幅。
///
/// 服务端只保留置信度 ≥ 0.7 的匹配，因此这里不做置信度分档展示——
/// 出现在这里的每一条都值得看一眼。
class SuggestionBanner extends StatelessWidget {
  final List<SuggestionItem> items;
  final void Function(int index) onAccept;
  final void Function(int index) onDismiss;

  const SuggestionBanner({
    super.key,
    required this.items,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.primarySofter(context),
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '发现 ${items.length} 条可能的关联',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.onPrimarySoft(context),
            ),
          ),
          const SizedBox(height: 4),
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[index].memoSnippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        Text(
                          '→「${items[index].threadTitle}」',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        Text(
                          items[index].reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: Key('suggestion_accept_$index'),
                    icon: const Icon(Icons.check, size: 18),
                    color: AppColors.primary,
                    tooltip: '加入',
                    onPressed: () => onAccept(index),
                  ),
                  IconButton(
                    key: Key('suggestion_dismiss_$index'),
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary(context),
                    tooltip: '忽略',
                    onPressed: () => onDismiss(index),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
