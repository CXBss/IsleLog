import 'package:flutter/material.dart';

import '../../../data/models/memo_entry.dart';
import '../../../features/memo_detail/memo_detail_page.dart';
import '../../../features/memo_editor/memo_editor_page.dart';
import '../../../shared/constants/app_constants.dart';

/// 搜索结果卡片
///
/// 显示日期+时间、关键词高亮正文、标签列表。
/// 不含时间轴装饰，专为搜索结果列表设计。
class MemoSearchCard extends StatelessWidget {
  final MemoEntry memo;

  /// 高亮关键词（大小写不敏感）
  final String query;

  const MemoSearchCard({super.key, required this.memo, required this.query});

  String get _dateTimeLabel {
    final d = memo.createdAt;
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  String get _displayContent {
    var text = memo.content;
    for (final tag in memo.tags) {
      text = text.replaceAll('#$tag', '');
    }
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => MemoDetailPage(memo: memo))),
      onDoubleTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => MemoEditorPage(editingMemo: memo))),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 日期时间 ──────────────────────────────────────
            Text(
              _dateTimeLabel,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),

            // ── 正文（高亮关键词）────────────────────────────
            if (_displayContent.isNotEmpty)
              _HighlightText(text: _displayContent, query: query),

            // ── 标签 ──────────────────────────────────────────
            if (memo.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: memo.tags
                    .map((tag) => _TagLabel(tag: tag))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

/// 带关键词高亮的文本组件
///
/// 将 [query] 在 [text] 中的所有匹配片段用黄色背景 + 加粗标注，
/// 大小写不敏感匹配，原始大小写保留显示。
class _HighlightText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) {
      return Text(
        text,
        style: const TextStyle(
            fontSize: 14, height: 1.6, color: AppColors.textBody),
        maxLines: 8,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = _buildSpans(text, query.trim().toLowerCase());
    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(
          fontSize: 14, height: 1.6, color: AppColors.textBody),
      maxLines: 8,
      overflow: TextOverflow.ellipsis,
    );
  }

  List<InlineSpan> _buildSpans(String text, String lowerQuery) {
    final spans = <InlineSpan>[];
    final lowerText = text.toLowerCase();
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        // 剩余普通文本
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start)));
        }
        break;
      }
      // 匹配前的普通文本
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      // 高亮片段
      spans.add(TextSpan(
        text: text.substring(idx, idx + lowerQuery.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFFE082),
          color: Color(0xFF4E3500),
          fontWeight: FontWeight.bold,
        ),
      ));
      start = idx + lowerQuery.length;
    }

    return spans;
  }
}

/// 搜索结果卡片中的标签标注
class _TagLabel extends StatelessWidget {
  final String tag;
  const _TagLabel({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '#$tag',
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
