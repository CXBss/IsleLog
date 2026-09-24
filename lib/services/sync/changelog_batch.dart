/// 一类实体在一批 changelog 里的净变化：要拉最新数据的，和要本地删除的。
class EntityChanges {
  final Set<String> upserts = {};
  final Set<String> deletes = {};
}

/// 一批 changelog 按实体归并后的结果，键都是本地存储用的远端资源名。
class ChangelogBatch {
  final EntityChanges memos = EntityChanges();
  final EntityChanges folders = EntityChanges();
  final EntityChanges articles = EntityChanges();
  final EntityChanges threads = EntityChanges();
}

/// 把服务端 changelog 列表归并成各实体的待拉取 / 待删除集合。
///
/// - 同一实体出现过 DELETE 就只删不拉：服务端 id 不复用，删除后不会再有同名实体。
/// - 文章的 changelog 资源名是 `articles/N`，但文章接口返回、本地
///   `ArticleEntry.articleName` 存的是 `memos/N`，这里统一成后者。
/// - comment / attachment 等其他实体不在此处理：附件变化服务端会另记一条
///   归属日记/文章的 UPDATE，评论目前仍靠详情页按需拉取。
ChangelogBatch groupChangelogs(List<Map<String, dynamic>> changelogs) {
  final batch = ChangelogBatch();
  for (final log in changelogs) {
    final entityId = log['entityId'] as String? ?? '';
    if (entityId.isEmpty) continue;
    final changes = switch (log['entity'] as String? ?? '') {
      'memo' => batch.memos,
      'folder' => batch.folders,
      'article' => batch.articles,
      'thread' => batch.threads,
      _ => null,
    };
    if (changes == null) continue;
    final name = log['entity'] == 'article'
        ? entityId.replaceFirst('articles/', 'memos/')
        : entityId;
    if (log['action'] == 'DELETE') {
      changes.deletes.add(name);
    } else {
      changes.upserts.add(name);
    }
  }
  for (final changes in [
    batch.memos,
    batch.folders,
    batch.articles,
    batch.threads,
  ]) {
    changes.upserts.removeAll(changes.deletes);
  }
  return batch;
}
