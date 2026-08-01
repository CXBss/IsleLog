import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

import '../../../services/ai/ai_models.dart';
import 'polish_result_controller.dart';

/// 润色结果预览页。
///
/// 每个片段显示原文到润色文本的 Diff、理由和复选框；底部提供
/// "全部接受""全部取消""应用所选"。页面只返回组合后的字符串，
/// 不修改 Memo、不保存、不同步。
class PolishPreviewPage extends StatefulWidget {
  final String original;
  final List<AiPolishSegment> segments;

  const PolishPreviewPage({
    super.key,
    required this.original,
    required this.segments,
  });

  @override
  State<PolishPreviewPage> createState() => _PolishPreviewPageState();
}

class _PolishPreviewPageState extends State<PolishPreviewPage> {
  late final PolishResultController _controller;
  String? _protectionError;

  @override
  void initState() {
    super.initState();
    _controller = PolishResultController(widget.original, widget.segments);
  }

  void _apply() {
    try {
      final result = _controller.buildText();
      Navigator.pop(context, result);
    } on StateError catch (e) {
      setState(() => _protectionError = e.message);
    }
  }

  void _setAll(bool accepted) {
    setState(() {
      for (var i = 0; i < widget.segments.length; i++) {
        _controller.setAccepted(i, accepted);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '润色预览',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.segments.length,
              itemBuilder: (context, index) {
                final segment = widget.segments[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SegmentCard(
                    segment: segment,
                    accepted: _controller.isAccepted(index),
                    onChanged: (checked) =>
                        setState(() => _controller.setAccepted(index, checked)),
                  ),
                );
              },
            ),
          ),
          if (_protectionError != null)
            Container(
              width: double.infinity,
              color: Colors.red.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '无法应用：$_protectionError',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _setAll(false),
                    child: const Text('全部取消'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _setAll(true),
                    child: const Text('全部接受'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _protectionError == null ? _apply : null,
                    child: const Text('应用所选'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  final AiPolishSegment segment;
  final bool accepted;
  final ValueChanged<bool> onChanged;

  const _SegmentCard({
    required this.segment,
    required this.accepted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: accepted,
                  onChanged: (checked) => onChanged(checked ?? false),
                ),
                Expanded(
                  child: Text(
                    '段落 ${segment.sourceIndexes.join(", ")}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _DiffText(
                original: segment.originalText,
                revised: segment.revisedText,
              ),
            ),
            if (segment.reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  segment.reason,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiffText extends StatelessWidget {
  final String original;
  final String revised;

  const _DiffText({required this.original, required this.revised});

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
        style: const TextStyle(
          fontSize: 14,
          height: 1.6,
          color: Colors.black87,
        ),
        children: spans,
      ),
    );
  }
}
