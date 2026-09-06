import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/article_entry.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/services/link/link_target.dart';
import 'package:isle_log/services/link/memo_link.dart';

MemoEntry _memo({
  required int id,
  String content = '正文',
  String? memosName,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => MemoEntry()
  ..id = id
  ..content = content
  ..memosName = memosName
  ..createdAt = createdAt ?? DateTime(2026, 3, 12)
  ..updatedAt = updatedAt ?? DateTime(2026, 3, 12);

ArticleEntry _article({
  required int id,
  String title = '标题',
  String? articleName,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => ArticleEntry()
  ..id = id
  ..title = title
  ..articleName = articleName
  ..createdAt = createdAt ?? DateTime(2026, 3, 12)
  ..updatedAt = updatedAt ?? DateTime(2026, 3, 12);

void main() {
  final now = DateTime(2026, 9, 6);

  test('日记映射出日期加摘要的标签', () {
    final targets = buildLinkTargets(
      memos: [_memo(id: 1, content: '深圳暴雨', memosName: 'memos/123')],
      articles: [],
      now: now,
    );

    expect(targets.single.kind, LinkKind.memo);
    expect(targets.single.localId, 1);
    expect(targets.single.remoteName, 'memos/123');
    expect(targets.single.label, '03-12 深圳暴雨');
    expect(targets.single.isSynced, isTrue);
  });

  test('文章映射出标题作为标签', () {
    final targets = buildLinkTargets(
      memos: [],
      articles: [_article(id: 7, title: '海岛日志设计稿', articleName: 'articles/7')],
      now: now,
    );

    expect(targets.single.kind, LinkKind.article);
    expect(targets.single.label, '海岛日志设计稿');
    expect(targets.single.preview, '海岛日志设计稿');
  });

  test('没有远端名的条目标记为未同步', () {
    final targets = buildLinkTargets(
      memos: [_memo(id: 1)],
      articles: [],
      now: now,
    );

    expect(targets.single.isSynced, isFalse);
    expect(targets.single.remoteName, isNull);
  });

  test('排除正在编辑的日记自己', () {
    final targets = buildLinkTargets(
      memos: [_memo(id: 1), _memo(id: 2)],
      articles: [],
      excludeMemoId: 1,
      now: now,
    );

    expect(targets.map((t) => t.localId), [2]);
  });

  test('排除正在编辑的文章自己', () {
    final targets = buildLinkTargets(
      memos: [],
      articles: [_article(id: 7), _article(id: 8)],
      excludeArticleId: 7,
      now: now,
    );

    expect(targets.map((t) => t.localId), [8]);
  });

  test('日记与文章按更新时间倒序混排', () {
    final targets = buildLinkTargets(
      memos: [
        _memo(id: 1, content: '旧', updatedAt: DateTime(2026, 1, 1)),
        _memo(id: 2, content: '新', updatedAt: DateTime(2026, 5, 1)),
      ],
      articles: [
        _article(id: 7, title: '中', updatedAt: DateTime(2026, 3, 1)),
      ],
      now: now,
    );

    expect(targets.map((t) => t.localId), [2, 7, 1]);
  });

  test('超过上限时截断', () {
    final targets = buildLinkTargets(
      memos: List.generate(30, (i) => _memo(id: i + 1)),
      articles: [],
      limit: 20,
      now: now,
    );

    expect(targets.length, 20);
  });

  test('日记预览取首行且去掉 Markdown 标记', () {
    final targets = buildLinkTargets(
      memos: [_memo(id: 1, content: '## 今天的记录\n第二行')],
      articles: [],
      now: now,
    );

    expect(targets.single.preview, '今天的记录');
  });
}
