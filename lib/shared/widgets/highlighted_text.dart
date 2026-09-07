import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// 把 [text] 中命中 [query] 的片段高亮显示。
///
/// [query] 为空时退化为普通 Text，不产生额外的 span 开销。
/// 大小写不敏感，与调用方的搜索口径保持一致。
class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final int maxLines;
  final TextStyle? style;

  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.maxLines = 3,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lower.indexOf(q, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + q.length),
          style: const TextStyle(
            backgroundColor: AppColors.primaryLight,
            color: AppColors.primaryDark,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = index + q.length;
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
