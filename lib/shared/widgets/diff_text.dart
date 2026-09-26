import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

/// 原文 → 改写的字符级对照：删除的标红划线，新增的标绿。
class DiffText extends StatelessWidget {
  final String original;
  final String revised;
  final double fontSize;

  const DiffText({
    super.key,
    required this.original,
    required this.revised,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(original, revised);
    final spans = <TextSpan>[];
    for (final diff in diffs) {
      switch (diff.operation) {
        case DIFF_DELETE:
          spans.add(
            TextSpan(
              text: diff.text,
              style: const TextStyle(
                color: Colors.red,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          );
        case DIFF_INSERT:
          spans.add(
            TextSpan(
              text: diff.text,
              style: const TextStyle(color: Color(0xFF2E7D32)),
            ),
          );
        case DIFF_EQUAL:
          spans.add(TextSpan(text: diff.text));
      }
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          height: 1.6,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        children: spans,
      ),
    );
  }
}
