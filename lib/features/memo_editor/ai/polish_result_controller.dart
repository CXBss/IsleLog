import 'package:isle_log/services/ai/ai_models.dart';
import 'package:isle_log/services/ai/markdown_protection.dart';

/// 润色结果组合控制器。
///
/// 接收请求时的完整原文与服务端返回的片段，初始不接受任何变更；
/// 使用与请求时一致的精确段落切分保留原始空白和分隔符。
class PolishResultController {
  final String original;
  final List<AiPolishSegment> segments;
  final List<bool> _accepted;
  late final List<SourceParagraph> _paragraphs;
  late final List<int> _segmentOfParagraph;

  PolishResultController(this.original, this.segments)
    : _accepted = List.filled(segments.length, false) {
    _paragraphs = MarkdownProtection.splitParagraphs(original);
    _validateSegments();
    _segmentOfParagraph = List.filled(_paragraphs.length, -1);
    for (var s = 0; s < segments.length; s++) {
      for (final index in segments[s].sourceIndexes) {
        _segmentOfParagraph[index] = s;
      }
    }
  }

  /// 校验片段来源索引与服务端规则一致：顺序、连续、每段恰好出现一次。
  void _validateSegments() {
    var expected = 0;
    for (var s = 0; s < segments.length; s++) {
      final indexes = segments[s].sourceIndexes;
      if (indexes.isEmpty) {
        throw ArgumentError('第 $s 个润色片段缺少来源段落索引');
      }
      for (var offset = 0; offset < indexes.length; offset++) {
        final index = indexes[offset];
        if (index < 0 || index >= _paragraphs.length) {
          throw ArgumentError('第 $s 个润色片段的来源索引 $index 越界');
        }
        if (offset > 0 && index != indexes[offset - 1] + 1) {
          throw ArgumentError('第 $s 个润色片段的来源索引必须严格连续升序');
        }
        if (index != expected) {
          throw ArgumentError('来源段落索引必须按顺序且每段恰好出现一次，期望 $expected，实际 $index');
        }
        expected++;
      }
    }
    if (expected != _paragraphs.length) {
      throw ArgumentError(
        '来源段落索引不完整：已覆盖 $expected 段，共 ${_paragraphs.length} 段',
      );
    }
  }

  /// 设置指定片段是否被接受。
  void setAccepted(int index, bool accepted) {
    _accepted[index] = accepted;
  }

  bool isAccepted(int index) => _accepted[index];

  /// 组合文本：只替换被接受片段对应的连续来源段落，其余保持原文。
  ///
  /// 全部拒绝时逐字返回原文；返回前执行全局保护校验，失败抛 [StateError]。
  String buildText() {
    final buffer = StringBuffer();
    var p = 0;
    while (p < _paragraphs.length) {
      final s = _segmentOfParagraph[p];
      if (s >= 0 && _accepted[s]) {
        final last = segments[s].sourceIndexes.last;
        buffer.write(segments[s].revisedText);
        buffer.write(_paragraphs[last].separator);
        p = last + 1;
      } else {
        buffer.write(_paragraphs[p].text);
        buffer.write(_paragraphs[p].separator);
        p++;
      }
    }
    final result = buffer.toString();
    final protection = MarkdownProtection.validate(original, result);
    if (!protection.isValid) {
      throw StateError('保护校验失败：${protection.message}');
    }
    return result;
  }
}
