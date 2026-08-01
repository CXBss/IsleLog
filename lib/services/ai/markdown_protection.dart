import 'package:flutter/foundation.dart' show listEquals;

/// 受保护内容校验结果。
class ProtectionValidation {
  final bool isValid;
  final String? message;

  const ProtectionValidation.valid() : isValid = true, message = null;

  const ProtectionValidation.invalid(this.message) : isValid = false;
}

/// 原文段落。`separator` 属于当前段落，保存正文之后、下一段正文之前的
/// 全部空行；拼接全部字段即可无损还原原文。
class SourceParagraph {
  final String text;
  final String separator;

  const SourceParagraph(this.text, [this.separator = '']);
}

/// Markdown 受保护元素校验。
///
/// 与服务端 `service/ai/protection.go` 使用同一组有序元素：
/// 标签、Markdown 链接或图片、待办标记、日期、数值字面量和围栏代码块。
class MarkdownProtection {
  MarkdownProtection._();

  static final _paragraphSeparator = RegExp(r'\r?\n(?:[ \t]*\r?\n)+');
  static final _tagPattern = RegExp(r'(?:^|[ \t\r\n\f\v])#([^ \t\r\n\f\v#]+)');
  static final _todoMarkerPattern = RegExp(r'- \[[ xX]\]');
  static final _datePattern = RegExp(
    r'\b\d{4}-\d{2}-\d{2}\b|\b\d{4}/\d{1,2}/\d{1,2}\b|\d{4}年\d{1,2}月\d{1,2}日',
  );
  static final _numberPattern = RegExp(
    r'[+-]?(?:0[xX][0-9A-Fa-f]+|0[bB][01]+|0[oO][0-7]+|(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?%?)',
  );

  /// 校验修订文本是否改变受保护内容。
  static ProtectionValidation validate(String original, String revised) {
    final want = _extractProtectedElements(original);
    final got = _extractProtectedElements(revised);
    final checks = [
      ('标签', want.tags, got.tags),
      ('Markdown 链接或图片', want.links, got.links),
      ('待办标记', want.todoMarkers, got.todoMarkers),
      ('日期', want.dates, got.dates),
      ('数值', want.numbers, got.numbers),
      ('围栏代码', want.codeBlocks, got.codeBlocks),
    ];
    for (final (category, wanted, received) in checks) {
      if (!listEquals(wanted, received)) {
        return ProtectionValidation.invalid('$category等受保护内容发生新增、删除、修改或顺序变化');
      }
    }
    return const ProtectionValidation.valid();
  }

  /// 按空行拆分原文，保留 LF、CRLF 和空白行内容，跳过围栏代码内部空行。
  static List<SourceParagraph> splitParagraphs(String original) {
    final matches = _paragraphSeparator.allMatches(original).toList();
    final codeSpans = _extractFencedCode(original).spans;
    final paragraphs = <SourceParagraph>[];
    var start = 0;
    for (final match in matches) {
      if (_positionInSpans(match.start, codeSpans)) continue;
      paragraphs.add(
        SourceParagraph(
          original.substring(start, match.start),
          original.substring(match.start, match.end),
        ),
      );
      start = match.end;
    }
    if (start < original.length || matches.isEmpty) {
      paragraphs.add(SourceParagraph(original.substring(start)));
    }
    return paragraphs;
  }

  // ── 保护元素提取 ──────────────────────────────────────────────

  static _ProtectedElements _extractProtectedElements(String text) {
    final code = _extractFencedCode(text);
    var masked = _maskSpans(text, code.spans);
    final inlineSpans = _extractInlineCodeSpans(masked);
    masked = _maskSpans(masked, inlineSpans);

    final tags = _extractTags(masked);
    final links = _extractMarkdownLinks(masked);
    final todo = _extractPatternTokens(masked, _todoMarkerPattern);
    final dates = _extractPatternTokens(masked, _datePattern);

    final numberInput = _maskSpans(masked, [
      ...tags.spans,
      ...links.spans,
      ...dates.spans,
    ]);
    final numbers = _extractNumbers(numberInput);
    return _ProtectedElements(
      tags: tags.tokens,
      links: links.tokens,
      todoMarkers: todo.tokens,
      dates: dates.tokens,
      numbers: numbers,
      codeBlocks: code.tokens,
    );
  }

  static ({List<_Span> spans, List<String> tokens}) _extractFencedCode(
    String text,
  ) {
    final spans = <_Span>[];
    final tokens = <String>[];
    var lineStart = 0;
    while (lineStart < text.length) {
      final line = _lineBounds(text, lineStart);
      final openingTicks = _parseFenceOpening(
        text.substring(line.start, line.end),
      );
      if (openingTicks == null) {
        lineStart = line.nextLine;
        continue;
      }

      var spanEnd = text.length;
      var nextLine = line.nextLine;
      var closingStart = line.nextLine;
      while (closingStart < text.length) {
        final closing = _lineBounds(text, closingStart);
        if (_isFenceClosing(
          text.substring(closing.start, closing.end),
          openingTicks,
        )) {
          spanEnd = closing.end;
          nextLine = closing.afterClosing;
          break;
        }
        closingStart = closing.afterClosing;
      }
      spans.add(_Span(lineStart, spanEnd));
      tokens.add(text.substring(lineStart, spanEnd));
      if (spanEnd == text.length) break;
      lineStart = nextLine;
    }
    return (spans: spans, tokens: tokens);
  }

  static ({int start, int end, int nextLine, int afterClosing}) _lineBounds(
    String text,
    int start,
  ) {
    final relativeEnd = text.indexOf('\n', start);
    if (relativeEnd < 0) {
      return (
        start: start,
        end: text.length,
        nextLine: text.length,
        afterClosing: text.length,
      );
    }
    var end = relativeEnd;
    final nextLine = relativeEnd + 1;
    if (end > start && text.codeUnitAt(end - 1) == 0x0d) end--;
    return (start: start, end: end, nextLine: nextLine, afterClosing: nextLine);
  }

  static int? _parseFenceOpening(String line) {
    final contentStart = _fenceIndentEnd(line);
    if (contentStart == null) return null;
    final ticks = _countLeadingBackticks(line, contentStart);
    if (ticks < 3 || line.substring(contentStart + ticks).contains('`')) {
      return null;
    }
    return ticks;
  }

  static bool _isFenceClosing(String line, int openingTicks) {
    final contentStart = _fenceIndentEnd(line);
    if (contentStart == null) return false;
    final ticks = _countLeadingBackticks(line, contentStart);
    if (ticks < openingTicks) return false;
    return line.substring(contentStart + ticks).trimWhitespaceOnly() == '';
  }

  static int? _fenceIndentEnd(String line) {
    var spaces = 0;
    while (spaces < line.length && line[spaces] == ' ') {
      spaces++;
    }
    return spaces <= 3 ? spaces : null;
  }

  static int _countLeadingBackticks(String text, int start) {
    var count = 0;
    while (start + count < text.length && text[start + count] == '`') {
      count++;
    }
    return count;
  }

  static List<_Span> _extractInlineCodeSpans(String text) {
    final spans = <_Span>[];
    var position = 0;
    while (position < text.length) {
      final relativeStart = text.indexOf('`', position);
      if (relativeStart < 0) break;
      final start = relativeStart;
      final openingLength = _countLeadingBackticks(text, start);
      if (_isEscaped(text, start)) {
        position = start + openingLength;
        continue;
      }
      var searchFrom = start + openingLength;
      var matched = false;
      while (searchFrom < text.length) {
        final relativeClosing = text.indexOf('`', searchFrom);
        if (relativeClosing < 0) break;
        final closingStart = relativeClosing;
        final closingLength = _countLeadingBackticks(text, closingStart);
        final closingEnd = closingStart + closingLength;
        if (_isEscaped(text, closingStart)) {
          searchFrom = closingEnd;
          continue;
        }
        if (closingLength == openingLength) {
          spans.add(_Span(start, closingEnd));
          position = closingEnd;
          matched = true;
          break;
        }
        searchFrom = closingEnd;
      }
      if (!matched) position = start + openingLength;
    }
    return spans;
  }

  static ({List<_Span> spans, List<String> tokens}) _extractTags(String text) {
    final spans = <_Span>[];
    final tokens = <String>[];
    for (final match in _tagPattern.allMatches(text)) {
      final group = match.group(1);
      if (group == null) continue;
      final spanStart = match.start + match.group(0)!.indexOf('#');
      spans.add(_Span(spanStart, match.end));
      tokens.add(text.substring(spanStart, match.end));
    }
    return (spans: spans, tokens: tokens);
  }

  static ({List<_Span> spans, List<String> tokens}) _extractMarkdownLinks(
    String text,
  ) {
    final spans = <_Span>[];
    final tokens = <String>[];
    var index = 0;
    while (index < text.length) {
      if (text[index] != '[' || _isEscaped(text, index)) {
        index++;
        continue;
      }
      var start = index;
      if (index > 0 && text[index - 1] == '!' && !_isEscaped(text, index - 1)) {
        start--;
      }

      final labelEnd = _findBalancedEnd(text, index + 1, '[', ']');
      if (labelEnd == null ||
          labelEnd + 1 >= text.length ||
          text[labelEnd + 1] != '(') {
        index++;
        continue;
      }
      final urlEnd = _findBalancedEnd(text, labelEnd + 2, '(', ')');
      final end = urlEnd == null
          ? _linkFallbackEnd(text, labelEnd + 2)
          : urlEnd + 1;
      spans.add(_Span(start, end));
      tokens.add(text.substring(start, end));
      index = end;
    }
    return (spans: spans, tokens: tokens);
  }

  static int _linkFallbackEnd(String text, int searchStart) {
    final relative = _indexOfNewline(text, searchStart);
    return relative < 0 ? text.length : relative;
  }

  static int _indexOfNewline(String text, int start) {
    final newline = text.indexOf('\n', start);
    final carriage = text.indexOf('\r', start);
    if (newline < 0) return carriage;
    if (carriage < 0) return newline;
    return newline < carriage ? newline : carriage;
  }

  static int? _findBalancedEnd(
    String text,
    int start,
    String opening,
    String closing,
  ) {
    var depth = 1;
    var index = start;
    while (index < text.length) {
      if (text[index] == '\r' || text[index] == '\n') return null;
      if (text[index] == '\\') {
        if (index + 1 < text.length) index++;
        index++;
        continue;
      }
      if (text[index] == opening) {
        depth++;
      } else if (text[index] == closing) {
        depth--;
        if (depth == 0) return index;
      }
      index++;
    }
    return null;
  }

  static bool _isEscaped(String text, int position) {
    var backslashes = 0;
    while (position > 0 && text[position - 1] == '\\') {
      backslashes++;
      position--;
    }
    return backslashes.isOdd;
  }

  static ({List<_Span> spans, List<String> tokens}) _extractPatternTokens(
    String text,
    RegExp pattern,
  ) {
    final spans = <_Span>[];
    final tokens = <String>[];
    for (final match in pattern.allMatches(text)) {
      spans.add(_Span(match.start, match.end));
      tokens.add(match.group(0)!);
    }
    return (spans: spans, tokens: tokens);
  }

  static List<String> _extractNumbers(String text) {
    final tokens = <String>[];
    for (final match in _numberPattern.allMatches(text)) {
      if (_isOrderedListNumber(text, match.start, match.end)) continue;
      tokens.add(match.group(0)!);
    }
    return tokens;
  }

  static bool _isOrderedListNumber(String text, int start, int end) {
    if (!_isUnsignedInteger(text.substring(start, end))) return false;
    final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    if (!_isMarkdownContainerPrefix(text.substring(lineStart, start)) ||
        end >= text.length) {
      return false;
    }
    if (text[end] != '.' && text[end] != ')') return false;
    if (end + 1 >= text.length) return true;
    final next = text[end + 1];
    return next == ' ' || next == '\t' || next == '\r' || next == '\n';
  }

  static bool _isUnsignedInteger(String token) {
    if (token.isEmpty) return false;
    for (var i = 0; i < token.length; i++) {
      if (token.codeUnitAt(i) < 0x30 || token.codeUnitAt(i) > 0x39) {
        return false;
      }
    }
    return true;
  }

  static bool _isMarkdownContainerPrefix(String prefix) {
    prefix = prefix.trim();
    while (prefix.isNotEmpty) {
      if (prefix.startsWith('>')) {
        prefix = prefix.substring(1).trim();
        continue;
      }
      if (prefix.length >= 2 &&
          (prefix[0] == '-' || prefix[0] == '+' || prefix[0] == '*') &&
          (prefix[1] == ' ' || prefix[1] == '\t')) {
        prefix = prefix.substring(2).trim();
        continue;
      }
      return false;
    }
    return true;
  }

  static bool _positionInSpans(int position, List<_Span> spans) {
    for (final span in spans) {
      if (position >= span.start && position < span.end) return true;
    }
    return false;
  }

  static String _maskSpans(String text, List<_Span> spans) {
    if (spans.isEmpty) return text;
    final chars = text.split('');
    for (final span in spans) {
      for (var i = span.start; i < span.end; i++) {
        final char = chars[i];
        if (char != '\n' && char != '\r') chars[i] = ' ';
      }
    }
    return chars.join();
  }
}

class _Span {
  final int start;
  final int end;

  const _Span(this.start, this.end);
}

class _ProtectedElements {
  final List<String> tags;
  final List<String> links;
  final List<String> todoMarkers;
  final List<String> dates;
  final List<String> numbers;
  final List<String> codeBlocks;

  const _ProtectedElements({
    required this.tags,
    required this.links,
    required this.todoMarkers,
    required this.dates,
    required this.numbers,
    required this.codeBlocks,
  });
}

extension _WhitespaceOnlyTrim on String {
  String trimWhitespaceOnly() {
    var start = 0;
    var end = length;
    while (start < end && (this[start] == ' ' || this[start] == '\t')) {
      start++;
    }
    while (end > start && (this[end - 1] == ' ' || this[end - 1] == '\t')) {
      end--;
    }
    return substring(start, end);
  }
}
