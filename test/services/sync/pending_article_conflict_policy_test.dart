import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/article_entry.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/services/sync/pending_article_conflict_policy.dart';

void main() {
  group('decidePendingArticle', () {
    test('pushes local edit when remote still matches edit baseline', () {
      // 最常见的场景：本地刚改完文章、远端没动。旧实现会在这里直接判冲突，
      // 让离线编辑永远推不上去。
      final local = ArticleEntry()
        ..title = '原标题'
        ..content = '本地新正文'
        ..originalTitle = '原标题'
        ..originalContent = '远端原正文'
        ..syncStatus = SyncStatus.pending;

      final decision = decidePendingArticle(
        local,
        _remoteArticle(title: '原标题', content: '远端原正文'),
        archived: false,
      );

      expect(decision, PendingArticleDecision.pushLocal);
    });

    test('reports conflict when remote changed from edit baseline', () {
      final local = ArticleEntry()
        ..title = '原标题'
        ..content = '本地新正文'
        ..originalTitle = '原标题'
        ..originalContent = '远端原正文'
        ..syncStatus = SyncStatus.pending;

      final decision = decidePendingArticle(
        local,
        _remoteArticle(title: '别台改的标题', content: '别台改的正文'),
        archived: false,
      );

      expect(decision, PendingArticleDecision.conflict);
    });

    test('recognizes retry when remote already equals local edit', () {
      final local = ArticleEntry()
        ..title = '标题'
        ..content = '本地新正文'
        ..originalTitle = '标题'
        ..originalContent = '远端原正文'
        ..syncStatus = SyncStatus.pending;

      final decision = decidePendingArticle(
        local,
        _remoteArticle(title: '标题', content: '本地新正文'),
        archived: false,
      );

      expect(decision, PendingArticleDecision.alreadySynced);
    });

    test('stays conservative when no edit baseline is available', () {
      final local = ArticleEntry()
        ..title = '标题'
        ..content = '本地新正文'
        ..syncStatus = SyncStatus.pending;

      final decision = decidePendingArticle(
        local,
        _remoteArticle(title: '标题', content: '远端正文'),
        archived: false,
      );

      expect(decision, PendingArticleDecision.conflict);
    });

    test('keeps a pending deletion pushable even when remote matches', () {
      // 离线删除文章：远端此刻必然还是同一份内容，不能让内容比对把删除吃掉。
      final local = ArticleEntry()
        ..title = '标题'
        ..content = '同一份正文'
        ..syncStatus = SyncStatus.pending
        ..isDeleted = true;

      final decision = decidePendingArticle(
        local,
        _remoteArticle(title: '标题', content: '同一份正文'),
        archived: false,
      );

      expect(decision, PendingArticleDecision.pushLocal);
    });

    test(
      'pushes local folder move when remote text still matches baseline',
      () {
        // 基线不记录文件夹；远端正文/标题仍等于基线，说明挪文件夹的是本地，
        // 应推送而非报冲突（删除文件夹时文章被提升到根目录就是这个场景）。
        final local = ArticleEntry()
          ..title = '标题'
          ..content = '正文'
          ..originalTitle = '标题'
          ..originalContent = '正文'
          ..folderName = 'folders/1'
          ..syncStatus = SyncStatus.pending;

        final decision = decidePendingArticle(
          local,
          _remoteArticle(title: '标题', content: '正文'),
          archived: false,
        );

        expect(decision, PendingArticleDecision.pushLocal);
      },
    );
  });

  group('captureArticleEditBaseline', () {
    test('takes current text as baseline for synced article', () {
      final article = ArticleEntry()
        ..title = '当前标题'
        ..content = '当前正文'
        ..originalTitle = '过期标题'
        ..originalContent = '过期正文'
        ..syncStatus = SyncStatus.synced;

      captureArticleEditBaseline(article);

      expect(article.originalTitle, '当前标题');
      expect(article.originalContent, '当前正文');
    });

    test('keeps existing baseline across repeated offline edits', () {
      final article = ArticleEntry()
        ..title = '第一次改的标题'
        ..content = '第一次改的正文'
        ..originalTitle = '远端标题'
        ..originalContent = '远端正文'
        ..syncStatus = SyncStatus.pending;

      captureArticleEditBaseline(article);

      expect(article.originalTitle, '远端标题');
      expect(article.originalContent, '远端正文');
    });

    test('fills missing baseline for pending article', () {
      final article = ArticleEntry()
        ..title = '标题'
        ..content = '正文'
        ..syncStatus = SyncStatus.pending;

      captureArticleEditBaseline(article);

      expect(article.originalTitle, '标题');
      expect(article.originalContent, '正文');
    });
  });

  group('markArticleSynced', () {
    test('clears edit and conflict snapshots', () {
      final article = ArticleEntry()
        ..syncStatus = SyncStatus.conflict
        ..originalTitle = 'baseline title'
        ..originalContent = 'baseline content'
        ..conflictRemoteTitle = 'remote title'
        ..conflictRemoteContent = 'remote content';
      final syncedAt = DateTime(2026, 9, 22, 12);

      markArticleSynced(article, syncedAt: syncedAt);

      expect(article.syncStatus, SyncStatus.synced);
      expect(article.lastSyncAt, syncedAt);
      expect(article.originalTitle, isNull);
      expect(article.originalContent, isNull);
      expect(article.conflictRemoteTitle, isNull);
      expect(article.conflictRemoteContent, isNull);
    });
  });
}

Map<String, dynamic> _remoteArticle({
  required String title,
  required String content,
}) {
  return {
    'title': title,
    'content': content,
    'pinned': false,
    'visibility': 'PRIVATE',
    'parent': null,
  };
}
