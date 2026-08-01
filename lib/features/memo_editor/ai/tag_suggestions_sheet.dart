import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/ai/ai_models.dart';

/// 展示 AI 标签建议审阅面板。
///
/// 最多五项，初始均不勾选；已有标签使用绿色，新标签显示"新建"徽标和
/// 虚线边框；确认后只返回勾选的标签名列表（未勾选时为空列表），取消返回 null。
Future<List<String>?> showTagSuggestionsSheet({
  required BuildContext context,
  required List<String> existingTags,
  required List<AiTagSuggestion> suggestions,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _TagSuggestionsSheet(
      existingTags: existingTags,
      suggestions: suggestions,
    ),
  );
}

class _TagSuggestionsSheet extends StatefulWidget {
  final List<String> existingTags;
  final List<AiTagSuggestion> suggestions;

  const _TagSuggestionsSheet({
    required this.existingTags,
    required this.suggestions,
  });

  @override
  State<_TagSuggestionsSheet> createState() => _TagSuggestionsSheetState();
}

class _TagSuggestionsSheetState extends State<_TagSuggestionsSheet> {
  late final Set<int> _selected = {};

  List<String> get _result => widget.suggestions
      .asMap()
      .entries
      .where((e) => _selected.contains(e.key))
      .map((e) => e.value.name)
      .toList();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final candidates = widget.suggestions.take(5).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'AI 标签建议',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < candidates.length; i++)
                    _SuggestionTile(
                      suggestion: candidates[i],
                      isExisting: widget.existingTags.contains(
                        candidates[i].name,
                      ),
                      selected: _selected.contains(i),
                      onChanged: (checked) => setState(() {
                        if (checked) {
                          _selected.add(i);
                        } else {
                          _selected.remove(i);
                        }
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _result),
                    child: const Text('确认'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final AiTagSuggestion suggestion;
  final bool isExisting;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _SuggestionTile({
    required this.suggestion,
    required this.isExisting,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = isExisting ? Colors.green : Colors.orange;
    return CheckboxListTile(
      value: selected,
      onChanged: (checked) => onChanged(checked ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      secondary: CustomPaint(
        painter: isExisting
            ? null
            : const DashedBorderPainter(color: Colors.orange),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: color.withValues(alpha: 0.06),
          ),
          child: Text(
            '#${suggestion.name}',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isExisting)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '新建',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text(
            '${(suggestion.confidence * 100).round()}%',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      subtitle: Text(
        suggestion.reason.isEmpty ? '没有说明' : suggestion.reason,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 虚线边框绘制器（避免引入外部依赖）。
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashGap;

  const DashedBorderPainter({
    required this.color,
    this.dashWidth = 4,
    this.dashGap = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashWidth, metric.length);
        dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + dashGap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
