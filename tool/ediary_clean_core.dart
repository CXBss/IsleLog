/// 一次性维护脚本的纯逻辑部分：把从旧日记 App 导出的、夹带 HTML 实体和
/// 残留标签的 Markdown 正文规范化。零依赖，可单测。
///
/// 主入口见 `tool/clean_ediary.dart`。
library;

/// 命名 HTML 实体表。`nbsp` 故意解成 U+00A0（不可断行空格）中间态，
/// 由 [_normalizeWhitespace] 再决定是「整行删掉」还是「转普通空格」。
/// 表外的命名实体一律原样保留，不猜。
const Map<String, String> _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'laquo': '«',
  'raquo': '»',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'times': '×',
  'divide': '÷',
  'middot': '·',
  'deg': '°',
  'plusmn': '±',
  'bull': '•',
  'dagger': '†',
  'sect': '§',
  'para': '¶',
  'ensp': ' ',
  'emsp': ' ',
  'thinsp': ' ',
  'hairsp': ' ',
};

/// 会被剥掉的 HTML 标签名（小写）。只动这些，其它 `<...>` 一律不碰，
/// 以免误伤 `List<T>`、`a<c` 这类正文。
const Set<String> _htmlTagAllowlist = {
  'p', 'div', 'span', 'font', 'center',
  'b', 'i', 'u', 's', 'strike', 'em', 'strong',
  'sub', 'sup', 'small', 'big', 'tt', 'code', 'mark', 'ins', 'del',
};

/// 剥掉后需要补一个换行的块级标签（其闭合标签 → `\n`）。
const Set<String> _blockTags = {'p', 'div', 'center'};

final RegExp _entityRe =
    RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]{1,31});');

final RegExp _tagRe = RegExp(r'</?([a-zA-Z][a-zA-Z0-9]*)(?:\s[^<>]*)?\s*/?>');

final RegExp _tagLike = RegExp(r'(?<!\S)#([^\s#]+)');

final RegExp _nbspRun = RegExp(' +');

String? _fromCodePoint(int? cp) {
  if (cp == null || cp < 0 || cp > 0x10FFFF) return null;
  if (cp >= 0xD800 && cp <= 0xDFFF) return null; // 代理区，非法单独码点
  try {
    return String.fromCharCode(cp);
  } catch (_) {
    return null;
  }
}

/// 单遍解码所有实体形式：每个匹配只替换一次，因此 `&amp;#50;` → `&#50;`
/// （而不是继续变成 `2`）。表外/非法实体原样返回。
String _decodeEntities(String input) {
  return input.replaceAllMapped(_entityRe, (m) {
    final body = m.group(1)!;
    if (body.length > 1 && (body[1] == 'x' || body[1] == 'X')) {
      return _fromCodePoint(int.tryParse(body.substring(2), radix: 16)) ??
          m.group(0)!;
    }
    if (body[0] == '#') {
      return _fromCodePoint(int.tryParse(body.substring(1))) ?? m.group(0)!;
    }
    return _namedEntities[body] ??
        _namedEntities[body.toLowerCase()] ??
        m.group(0)!;
  });
}

/// 只剥白名单标签：开标签删除、`<br>` → 换行、块级闭合标签 → 换行，
/// 其余白名单闭合标签删除。非白名单 `<...>` 原样保留。
String _stripHtmlTags(String input) {
  return input.replaceAllMapped(_tagRe, (m) {
    final name = m.group(1)!.toLowerCase();
    if (name == 'br') return '\n';
    if (!_htmlTagAllowlist.contains(name)) return m.group(0)!;
    final isClosing = m.group(0)!.startsWith('</');
    if (isClosing && _blockTags.contains(name)) return '\n';
    return '';
  });
}

/// 逐行处理空白：整行只剩空白（含 NBSP）→ 空行；行内 NBSP 连续段 →
/// 一个普通空格；清掉行尾空白。普通空格之间不折叠，避免动到代码块缩进。
String _normalizeWhitespace(String input) {
  final out = <String>[];
  for (var line in input.split('\n')) {
    if (line.trim().isEmpty) {
      out.add(''); // String.trim() 按 Unicode White_Space，含 U+00A0
      continue;
    }
    line = line.replaceAll(_nbspRun, ' ');
    line = line.replaceAll(RegExp(r'[ \t]+$'), '');
    out.add(line);
  }
  return out.join('\n');
}

/// 规范化一条从旧 App 导入的日记正文。
///
/// 先剥标签、再解实体：这样只有「真的以裸标签形式存在」的 `<br>`、`<div>`
/// 才会被当成标签处理；用户自己转义过的 `&lt;b&gt;` 解码后是字面 `<b>`，
/// 保留为正文。代价是对含转义标签的正文不是严格幂等（脚本只跑一次，可接受）。
String cleanEdiaryContent(String input) {
  var text = _stripHtmlTags(input);
  text = _decodeEntities(text);
  // 旧导出器把条目内的小节标题 `# 标题` 过度转义成了 `\#`。按用户要求只还原
  // 这一种转义（`\* \_ \> \-` 等保持不动）。`\#` 后若紧跟非空白（少数漏了
  // 空格的标题，如 `\#关于空调`），补一个空格再还原——否则行首那几条会被
  // extractTags 认成 `#关于空调` 这样的新标签，污染标签栏。
  text = text.replaceAllMapped(
    RegExp(r'\\#(\S?)'),
    (m) => m.group(1)!.isEmpty ? '#' : '# ${m.group(1)}',
  );
  // 旧导出器把段末的软换行标记转义成了 `\|\|`（渲染出来是 `||`）。按用户要求
  // 只去反斜杠：`\|` → `|`。这批数据没有 Markdown 表格，不存在误伤表格转义竖线。
  text = text.replaceAll(r'\|', '|');
  text = _normalizeWhitespace(text);
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n'); // 多空行 → 一个空行
  text = text.replaceAll(RegExp(r'^\n+'), '').replaceAll(RegExp(r'\n+$'), '');
  return text;
}

/// 与 `DatabaseService.extractTags` 同规则，脚本写回时用它重算 tags 索引。
List<String> extractTagsLike(String content) {
  return _tagLike
      .allMatches(content)
      .map((m) => m.group(1)!)
      .where((t) => t.isNotEmpty)
      .toList();
}
