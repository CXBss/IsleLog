import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/link/link_backfill.dart';
import 'package:isle_log/services/link/memo_link.dart';

/// 固定的假查询：45 → memos/500，12 → articles/7，其余查不到。
String? _lookup(LinkKind kind, int localId) {
  if (kind == LinkKind.memo && localId == 45) return 'memos/500';
  if (kind == LinkKind.article && localId == 12) return 'articles/7';
  return null;
}

void main() {
  group('bareLinkTargets', () {
    test('找出光杆日记链接的目标 id', () {
      const content = '见[03-12 暴雨](islelog://memo?lid=45)那天';

      expect(bareLinkTargets(content, LinkKind.memo), {45});
    });

    test('已完整的链接不算光杆', () {
      const content = '见[03-12 暴雨](islelog://memo/memos/500?lid=45)那天';

      expect(bareLinkTargets(content, LinkKind.memo), isEmpty);
    });

    test('只返回指定类型的目标', () {
      const content =
          '[a](islelog://memo?lid=45) 和 [b](islelog://article?lid=12)';

      expect(bareLinkTargets(content, LinkKind.memo), {45});
      expect(bareLinkTargets(content, LinkKind.article), {12});
    });

    test('没有链接时返回空集', () {
      expect(bareLinkTargets('普通正文', LinkKind.memo), isEmpty);
    });

    test('同一目标出现多次只算一个', () {
      const content =
          '[a](islelog://memo?lid=45) 又 [b](islelog://memo?lid=45)';

      expect(bareLinkTargets(content, LinkKind.memo), {45});
    });

    test('显示文字里的同名串不算目标', () {
      const content = '[islelog://memo?lid=45](https://example.com)';

      expect(bareLinkTargets(content, LinkKind.memo), isEmpty);
    });
  });

  group('backfillLinks', () {
    test('光杆链接且目标可解析时补上远端名', () {
      const content = '见[03-12 暴雨](islelog://memo?lid=45)那天';

      expect(
        backfillLinks(content, _lookup),
        '见[03-12 暴雨](islelog://memo/memos/500?lid=45)那天',
      );
    });

    test('补全后仍保留 lid', () {
      final result = backfillLinks('[a](islelog://memo?lid=45)', _lookup);

      expect(result, contains('lid=45'));
    });

    test('目标查不到时原样保留', () {
      const content = '[a](islelog://memo?lid=999)';

      expect(backfillLinks(content, _lookup), content);
    });

    test('已完整的链接不被重写', () {
      const content = '[a](islelog://memo/memos/123?lid=45)';

      expect(backfillLinks(content, _lookup), content);
    });

    test('文章链接同样补全', () {
      expect(
        backfillLinks('[a](islelog://article?lid=12)', _lookup),
        '[a](islelog://article/articles/7?lid=12)',
      );
    });

    test('一条正文里多个链接分别处理', () {
      const content =
          '[a](islelog://memo?lid=45)、[b](islelog://memo?lid=999)、'
          '[c](islelog://article?lid=12)';

      expect(
        backfillLinks(content, _lookup),
        '[a](islelog://memo/memos/500?lid=45)、[b](islelog://memo?lid=999)、'
        '[c](islelog://article/articles/7?lid=12)',
      );
    });

    test('没有内链的正文原样返回', () {
      const content = '普通正文，还有个外链 https://example.com';

      expect(backfillLinks(content, _lookup), content);
    });

    test('畸形的 islelog 串不被改动', () {
      const content = '[a](islelog://folder?lid=45) [b](islelog://memo)';

      expect(backfillLinks(content, _lookup), content);
    });

    test('跑两遍结果相同（幂等）', () {
      const content =
          '[a](islelog://memo?lid=45)、[b](islelog://article?lid=12)';

      final once = backfillLinks(content, _lookup);
      final twice = backfillLinks(once, _lookup);

      expect(twice, once);
    });

    test('查询返回空串视为查不到', () {
      String? emptyLookup(LinkKind kind, int localId) => '';
      const content = '[a](islelog://memo?lid=45)';

      expect(backfillLinks(content, emptyLookup), content);
    });

    test('链接显示文字里的同名串不被改写', () {
      // labelForMemo 取目标首行做标签，首行里若粘过内链地址，标签就会带着它。
      // 回写只能动 URI，不能动用户看得见的文字。
      const content = '[islelog://memo?lid=45](https://example.com)';

      expect(backfillLinks(content, _lookup), content);
    });

    test('纯文本里裸写的地址不被改写', () {
      const content = '我把地址贴在这儿：islelog://memo?lid=45';

      expect(backfillLinks(content, _lookup), content);
    });
  });
}

