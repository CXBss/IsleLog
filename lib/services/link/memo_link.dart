/// 内链（日记 ↔ 文章互相引用）的链接格式。
///
/// 正文里存的是标准 Markdown 链接，目标用自定义 scheme：
///
/// ```
/// [03-12 深圳暴雨地铁停…](islelog://memo/memos/123?lid=45)
/// [草稿：年终总结](islelog://memo?lid=45)
/// [《海岛日志设计稿》](islelog://article/articles/7?lid=12)
/// ```
///
/// 双标识的理由见 docs/superpowers/specs/2026-09-06-inline-links-design.md：
/// 远端名跨设备有效但未同步条目没有，本地 id 一定有但只在本机有意义。
///
/// 本文件是零依赖纯函数模块，不要在这里引入 Flutter 或 Isar。
library;

/// 链接目标的类型。
enum LinkKind { memo, article }

/// 一条内链解析后的结果。
class MemoLinkRef {
  final LinkKind kind;

  /// 远端资源名，如 "memos/123" / "articles/7"；目标未同步时为 null。
  final String? remoteName;

  /// 目标在本机 Isar 的自增主键；缺失时为 null。
  final int? localId;

  const MemoLinkRef({required this.kind, this.remoteName, this.localId});
}

class MemoLink {
  MemoLink._();

  static const String scheme = 'islelog';

  static const int _summaryMaxChars = 12;

  /// 构造链接 URI。远端名整段进 path，不做字符替换。
  static String build({
    required LinkKind kind,
    String? remoteName,
    int? localId,
  }) {
    final host = kind == LinkKind.memo ? 'memo' : 'article';
    final path = (remoteName == null || remoteName.isEmpty)
        ? ''
        : '/$remoteName';
    final query = localId == null ? '' : '?lid=$localId';
    return '$scheme://$host$path$query';
  }

  /// 解析链接 URI；不是内链、或两个标识都缺失时返回 null。
  static MemoLinkRef? parse(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null || uri.scheme != scheme) return null;

    final LinkKind kind;
    switch (uri.host) {
      case 'memo':
        kind = LinkKind.memo;
      case 'article':
        kind = LinkKind.article;
      default:
        return null;
    }

    final rawPath = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final remoteName = rawPath.isEmpty ? null : rawPath;
    final localId = int.tryParse(uri.queryParameters['lid'] ?? '');

    // 两个标识都没有的链接无法定位任何条目，视为非法。
    if (remoteName == null && localId == null) return null;

    return MemoLinkRef(kind: kind, remoteName: remoteName, localId: localId);
  }

  /// 清洗链接显示文字。
  ///
  /// 方括号会撑破 `[label](uri)` 语法，换行会让内联链接失效，
  /// `#标签` 一旦原样带进引用方正文，会被 `extractTags` 重新识别成
  /// 引用方自己的标签（污染标签侧栏），因此都必须在拼 Markdown 之前处理掉。
  static String sanitizeLabel(String raw) => raw
      .replaceAll(RegExp(r'[\[\]]'), '')
      .replaceAll(RegExp(r'(?<!\S)#'), '') // 不能让目标的标签跟着标签跑进引用方
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// 取正文第一行有内容的文字，并去掉常见 Markdown 标记。
  static String firstLineSummary(String content) {
    for (final rawLine in content.split('\n')) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      // 行首块级标记：标题 / 引用 / 待办 / 列表
      line = line.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
      line = line.replaceFirst(RegExp(r'^>\s*'), '');
      line = line.replaceFirst(RegExp(r'^[-*+]\s+\[[ xX]\]\s*'), '');
      line = line.replaceFirst(RegExp(r'^[-*+]\s+'), '');
      line = line.replaceFirst(RegExp(r'^\d+\.\s+'), '');
      // 已有的 Markdown 链接与图片只保留文字部分
      line = line.replaceAllMapped(
        RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      );
      // 行内强调标记
      line = line.replaceAll(RegExp(r'(\*{1,3}|_{1,3}|~~|`)'), '');
      line = line.trim();
      if (line.isNotEmpty) return line;
    }
    return '';
  }

  /// 日记的链接显示文字：`MM-DD 首行摘要`，跨年时写全年份。
  static String labelForMemo({
    required String content,
    required DateTime createdAt,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final mm = createdAt.month.toString().padLeft(2, '0');
    final dd = createdAt.day.toString().padLeft(2, '0');
    final datePart = createdAt.year == today.year
        ? '$mm-$dd'
        : '${createdAt.year}-$mm-$dd';

    final summary = sanitizeLabel(_truncate(firstLineSummary(content)));
    return summary.isEmpty ? datePart : '$datePart $summary';
  }

  /// 文章的链接显示文字就是标题；标题为空时给一个占位。
  static String labelForArticle(String title) {
    final label = sanitizeLabel(title);
    return label.isEmpty ? '未命名文章' : label;
  }

  /// 拼出可直接插入正文的 Markdown 链接。
  static String markdown({
    required String label,
    required LinkKind kind,
    String? remoteName,
    int? localId,
  }) {
    final uri = build(kind: kind, remoteName: remoteName, localId: localId);
    return '[${sanitizeLabel(label)}]($uri)';
  }

  /// 按码点截断，避免把中文或 emoji 从中间劈开。
  static String _truncate(String text) {
    final runes = text.runes.toList();
    if (runes.length <= _summaryMaxChars) return text;
    return '${String.fromCharCodes(runes.take(_summaryMaxChars))}…';
  }
}
