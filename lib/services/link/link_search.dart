import '../../data/database/database_service.dart';
import '../../data/models/article_entry.dart';
import '../../data/models/memo_entry.dart';
import 'link_query.dart';
import 'link_target.dart';
import 'memo_link.dart';

/// 选择器使用的搜索入口签名。
///
/// 抽成 typedef 是为了让 widget 测试注入假数据，不必拖起 Isar。
typedef LinkSearchFn =
    Future<List<LinkTarget>> Function(LinkQuery query, LinkKind? kind);

/// 按 [query] 查出可作为链接目标的日记与文章。
///
/// [kind] 为 null 表示两种都要。归档、已删除、私密空间条目均不在结果内
/// （vault 是独立的加密存储，本来就不经过 DatabaseService）。
Future<List<LinkTarget>> searchLinkTargets(
  LinkQuery query,
  LinkKind? kind, {
  int? excludeMemoId,
  int? excludeArticleId,
}) async {
  final wantMemo = kind == null || kind == LinkKind.memo;
  final wantArticle = kind == null || kind == LinkKind.article;

  var memos = <MemoEntry>[];
  var articles = <ArticleEntry>[];
  var limit = 50;

  if (query.isDate) {
    if (wantMemo) {
      memos = await DatabaseService.getMemosBetween(query.start!, query.end!);
    }
    if (wantArticle) {
      articles = await DatabaseService.getArticlesBetween(
        query.start!,
        query.end!,
      );
    }
  } else if (query.isKeyword) {
    if (wantMemo) memos = await DatabaseService.searchMemos(query.keyword);
    if (wantArticle) {
      articles = await DatabaseService.searchArticles(query.keyword);
      // searchArticles 不过滤归档，这里补上。
      articles = articles.where((a) => !a.isArchived).toList();
    }
  } else {
    // 空输入：列最近更新的条目，不输入也能选。
    // spec 第 5 节规定这条分支只列 20 条，别改回 50。
    if (wantMemo) memos = await DatabaseService.getRecentMemos(limit: 20);
    if (wantArticle) {
      articles = await DatabaseService.getRecentArticles(limit: 20);
    }
    limit = 20;
  }

  return buildLinkTargets(
    memos: memos,
    articles: articles,
    excludeMemoId: excludeMemoId,
    excludeArticleId: excludeArticleId,
    limit: limit,
  );
}
