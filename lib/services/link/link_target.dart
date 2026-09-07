import '../../data/models/article_entry.dart';
import '../../data/models/memo_entry.dart';
import 'memo_link.dart';

/// 选择器列表里的一行：一个可被插入为链接的目标。
class LinkTarget {
  final LinkKind kind;

  /// 目标在本机 Isar 的自增主键。
  final int localId;

  /// 远端资源名，未同步时为 null。
  final String? remoteName;

  /// 插入正文时使用的显示文字。
  final String label;

  /// 列表里展示的摘要：日记取首行，文章取标题。
  final String preview;

  final DateTime createdAt;
  final DateTime updatedAt;

  const LinkTarget({
    required this.kind,
    required this.localId,
    required this.remoteName,
    required this.label,
    required this.preview,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSynced => remoteName != null;

  /// 拼出可直接插入正文的 Markdown 链接。
  String toMarkdown() => MemoLink.markdown(
    label: label,
    kind: kind,
    remoteName: remoteName,
    localId: localId,
  );
}

/// 把查库结果映射成选择器行，按更新时间倒序混排并截断。
///
/// 纯函数，不碰数据库——查询条件由 [searchLinkTargets] 负责。
List<LinkTarget> buildLinkTargets({
  required List<MemoEntry> memos,
  required List<ArticleEntry> articles,
  int? excludeMemoId,
  int? excludeArticleId,
  DateTime? now,
  int limit = 50,
}) {
  final targets = <LinkTarget>[];

  for (final memo in memos) {
    if (memo.id == excludeMemoId) continue;
    targets.add(
      LinkTarget(
        kind: LinkKind.memo,
        localId: memo.id,
        remoteName: memo.memosName,
        label: MemoLink.labelForMemo(
          content: memo.content,
          createdAt: memo.createdAt,
          now: now,
        ),
        preview: MemoLink.firstLineSummary(memo.content),
        createdAt: memo.createdAt,
        updatedAt: memo.updatedAt,
      ),
    );
  }

  for (final article in articles) {
    if (article.id == excludeArticleId) continue;
    final label = MemoLink.labelForArticle(article.title);
    targets.add(
      LinkTarget(
        kind: LinkKind.article,
        localId: article.id,
        remoteName: article.articleName,
        label: label,
        preview: label,
        createdAt: article.createdAt,
        updatedAt: article.updatedAt,
      ),
    );
  }

  targets.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return targets.length <= limit ? targets : targets.sublist(0, limit);
}
