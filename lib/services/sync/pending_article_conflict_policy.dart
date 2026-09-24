import '../../data/models/article_entry.dart';
import '../../data/models/memo_entry.dart' show SyncStatus;

/// Pull 到远端文章、而本地该文章处于 `pending` 时该采取的动作。
enum PendingArticleDecision { alreadySynced, pushLocal, conflict }

/// 判断远端文章与本地待推送版本的关系。
///
/// 与 `decidePendingMemo` 同构，区别只在文章比 memo 多出 title / visibility /
/// parent 三个可比字段：
/// - 三方相同（远端 == 本地）→ 本次 push 其实已经生效，回到 synced；
/// - 远端仍等于编辑基线（[ArticleEntry.originalTitle] + [ArticleEntry.originalContent]）
///   → 保留 pending 等推送（**这是最常走的分支**：本地刚改完、远端没动）；
/// - 其余 → 双方都改了，标冲突等用户处理。
///
/// 没有这个函数时，pull 阶段对任何 pending 文章一律标 conflict（`_pullArticles`
/// 的旧实现），离线编辑的文章只要碰上 `syncAll`（App 启动、文章页刷新、删日记后
/// 的自动同步）就会被判冲突并停止推送，而冲突态在文章列表里没有任何入口。
PendingArticleDecision decidePendingArticle(
  ArticleEntry local,
  Map<String, dynamic> remote, {
  required bool archived,
}) {
  // 待删除条目直接交还推送端，理由同 memo：远端此刻必然还是旧内容，
  // 按内容判定会把删除意图改成 synced/conflict，删除就再也推不出去了。
  if (local.isDeleted) return PendingArticleDecision.pushLocal;

  if (_articlesMatch(local, remote, archived)) {
    return PendingArticleDecision.alreadySynced;
  }

  final remoteContent = remote['content'] as String? ?? '';
  final remoteTitle = remote['title'] as String? ?? '';
  if (local.originalContent != null &&
      remoteContent == local.originalContent &&
      remoteTitle == (local.originalTitle ?? '')) {
    return PendingArticleDecision.pushLocal;
  }

  return PendingArticleDecision.conflict;
}

/// 在本地改动文章**之前**记录编辑基线（标题 + 正文）。
///
/// - 已同步的文章：远端此刻就等于当前内容，基线直接取当前值（顺带覆盖掉
///   旧版本推送后没清理干净的过期基线）；
/// - 待推送 / 冲突中的文章：基线已记录的是「上一次与远端一致时」的内容，
///   必须保留，否则第二次离线编辑会把未推送的本地内容当成基线，拉取时误判冲突；
///   只有从未记录过基线时才补上。
void captureArticleEditBaseline(ArticleEntry article) {
  if (article.syncStatus == SyncStatus.synced ||
      article.originalContent == null) {
    article
      ..originalContent = article.content
      ..originalTitle = article.title;
  }
}

/// 标记文章已与远端一致，并清掉编辑基线与冲突快照。
void markArticleSynced(ArticleEntry article, {DateTime? syncedAt}) {
  article
    ..syncStatus = SyncStatus.synced
    ..lastSyncAt = syncedAt ?? DateTime.now()
    ..originalContent = null
    ..originalTitle = null
    ..conflictRemoteContent = null
    ..conflictRemoteTitle = null;
}

/// 本地文章与远端数据是否逐字段一致（用于识别「push 已生效」的重试）。
bool _articlesMatch(
  ArticleEntry local,
  Map<String, dynamic> remote,
  bool archived,
) {
  if (local.title != (remote['title'] as String? ?? '')) return false;
  if (local.content != (remote['content'] as String? ?? '')) return false;
  if (local.isPinned != (remote['pinned'] as bool? ?? false)) return false;
  if (local.isArchived != archived) return false;
  if (local.folderName != (remote['parent'] as String?)) return false;
  if (local.visibility != (remote['visibility'] as String? ?? 'PRIVATE')) {
    return false;
  }
  return true;
}
