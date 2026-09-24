import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/sync/changelog_batch.dart';

Map<String, dynamic> _log(String entity, String entityId, String action) => {
  'entity': entity,
  'entityId': entityId,
  'action': action,
};

void main() {
  group('groupChangelogs', () {
    test('routes each entity to its own bucket', () {
      final batch = groupChangelogs([
        _log('memo', 'memos/1', 'UPDATE'),
        _log('folder', 'folders/2', 'CREATE'),
        _log('article', 'articles/3', 'UPDATE'),
        _log('thread', 'threads/4', 'DELETE'),
      ]);

      expect(batch.memos.upserts, {'memos/1'});
      expect(batch.folders.upserts, {'folders/2'});
      expect(batch.articles.upserts, {'memos/3'});
      expect(batch.threads.deletes, {'threads/4'});
    });

    test('maps article resource names to the memos/ form stored locally', () {
      // 文章接口返回 name=memos/N，本地 articleName 也存这个；
      // changelog 却记成 articles/N，不转换就永远匹配不上本地文章。
      final batch = groupChangelogs([
        _log('article', 'articles/7', 'UPDATE'),
        _log('article', 'articles/8', 'DELETE'),
      ]);

      expect(batch.articles.upserts, {'memos/7'});
      expect(batch.articles.deletes, {'memos/8'});
    });

    test('delete wins over earlier or later updates of the same entity', () {
      final batch = groupChangelogs([
        _log('folder', 'folders/1', 'CREATE'),
        _log('folder', 'folders/1', 'UPDATE'),
        _log('folder', 'folders/1', 'DELETE'),
        _log('memo', 'memos/2', 'DELETE'),
        _log('memo', 'memos/2', 'UPDATE'),
      ]);

      expect(batch.folders.upserts, isEmpty);
      expect(batch.folders.deletes, {'folders/1'});
      expect(batch.memos.upserts, isEmpty);
      expect(batch.memos.deletes, {'memos/2'});
    });

    test('ignores comment, attachment and malformed records', () {
      final batch = groupChangelogs([
        _log('comment', 'memos/9', 'CREATE'),
        _log('attachment', 'attachments/5', 'UPDATE'),
        _log('memo', '', 'UPDATE'),
        {'id': 1},
      ]);

      for (final changes in [
        batch.memos,
        batch.folders,
        batch.articles,
        batch.threads,
      ]) {
        expect(changes.upserts, isEmpty);
        expect(changes.deletes, isEmpty);
      }
    });
  });
}
