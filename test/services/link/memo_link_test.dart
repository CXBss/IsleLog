import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/link/memo_link.dart';

void main() {
  group('build', () {
    test('已同步日记带远端名和本地 id', () {
      expect(
        MemoLink.build(kind: LinkKind.memo, remoteName: 'memos/123', localId: 45),
        'islelog://memo/memos/123?lid=45',
      );
    });

    test('未同步日记只带本地 id', () {
      expect(
        MemoLink.build(kind: LinkKind.memo, localId: 45),
        'islelog://memo?lid=45',
      );
    });

    test('文章用 article 作为 host', () {
      expect(
        MemoLink.build(kind: LinkKind.article, remoteName: 'articles/7', localId: 12),
        'islelog://article/articles/7?lid=12',
      );
    });
  });

  group('parse', () {
    test('解析出类型、远端名和本地 id', () {
      final ref = MemoLink.parse('islelog://memo/memos/123?lid=45')!;
      expect(ref.kind, LinkKind.memo);
      expect(ref.remoteName, 'memos/123');
      expect(ref.localId, 45);
    });

    test('未同步链接的远端名为 null', () {
      final ref = MemoLink.parse('islelog://memo?lid=45')!;
      expect(ref.remoteName, isNull);
      expect(ref.localId, 45);
    });

    test('文章链接', () {
      final ref = MemoLink.parse('islelog://article/articles/7?lid=12')!;
      expect(ref.kind, LinkKind.article);
      expect(ref.remoteName, 'articles/7');
    });

    test('build 与 parse 往返一致', () {
      const cases = [
        (LinkKind.memo, 'memos/1', 2),
        (LinkKind.article, 'articles/9', 8),
      ];
      for (final (kind, name, lid) in cases) {
        final href = MemoLink.build(kind: kind, remoteName: name, localId: lid);
        final ref = MemoLink.parse(href)!;
        expect(ref.kind, kind);
        expect(ref.remoteName, name);
        expect(ref.localId, lid);
      }
    });

    test('非 islelog scheme 返回 null', () {
      expect(MemoLink.parse('https://example.com/a'), isNull);
    });

    test('未知 host 返回 null', () {
      expect(MemoLink.parse('islelog://folder/folders/1?lid=3'), isNull);
    });

    test('既无远端名也无本地 id 返回 null', () {
      expect(MemoLink.parse('islelog://memo'), isNull);
    });

    test('lid 不是数字时按未同步处理但保留远端名', () {
      final ref = MemoLink.parse('islelog://memo/memos/123?lid=abc')!;
      expect(ref.remoteName, 'memos/123');
      expect(ref.localId, isNull);
    });

    test('非法字符串返回 null 而不抛异常', () {
      expect(MemoLink.parse('::::'), isNull);
      expect(MemoLink.parse(''), isNull);
    });
  });

  group('sanitizeLabel', () {
    test('去掉方括号，避免撑破 Markdown 链接语法', () {
      expect(MemoLink.sanitizeLabel('这是[重点]内容'), '这是重点内容');
    });

    test('换行和制表符压成单个空格', () {
      expect(MemoLink.sanitizeLabel('第一行\n第二行\t尾巴'), '第一行 第二行 尾巴');
    });

    test('连续空白折叠并去掉首尾空白', () {
      expect(MemoLink.sanitizeLabel('  a    b  '), 'a b');
    });

    test('去掉标签的 # 号，避免被 extractTags 重新识别成引用方的标签', () {
      expect(MemoLink.sanitizeLabel('#随笔 今天下雨'), '随笔 今天下雨');
    });

    test('# 不在标签位置（前面紧跟非空白字符）时原样保留', () {
      expect(MemoLink.sanitizeLabel('C#语言'), 'C#语言');
    });
  });

  group('firstLineSummary', () {
    test('去掉标题标记', () {
      expect(MemoLink.firstLineSummary('## 今天的记录\n正文'), '今天的记录');
    });

    test('去掉待办标记', () {
      expect(MemoLink.firstLineSummary('- [ ] 买菜'), '买菜');
    });

    test('去掉引用和列表标记', () {
      expect(MemoLink.firstLineSummary('> 引用一句'), '引用一句');
      expect(MemoLink.firstLineSummary('- 列表项'), '列表项');
      expect(MemoLink.firstLineSummary('1. 第一条'), '第一条');
    });

    test('去掉行内粗体斜体和代码标记', () {
      expect(MemoLink.firstLineSummary('**加粗**和`代码`'), '加粗和代码');
    });

    test('已有的 Markdown 链接只保留文字', () {
      expect(
        MemoLink.firstLineSummary('见[03-12 暴雨](islelog://memo?lid=1)那天'),
        '见03-12 暴雨那天',
      );
    });

    test('跳过开头的空行取第一行有内容的', () {
      expect(MemoLink.firstLineSummary('\n\n真正的首行'), '真正的首行');
    });

    test('全空内容返回空串', () {
      expect(MemoLink.firstLineSummary('   \n\n '), '');
    });
  });

  group('labelForMemo', () {
    final now = DateTime(2026, 9, 6);

    test('同年只写月日，摘要截到 12 字', () {
      final label = MemoLink.labelForMemo(
        content: '深圳暴雨地铁停运了整整一个下午',
        createdAt: DateTime(2026, 3, 12),
        now: now,
      );
      // 摘要按码点截到 12 个字：深圳暴雨地铁停运了整整一
      expect(label, '03-12 深圳暴雨地铁停运了整整一…');
    });

    test('短摘要不加省略号', () {
      final label = MemoLink.labelForMemo(
        content: '晴',
        createdAt: DateTime(2026, 3, 12),
        now: now,
      );
      expect(label, '03-12 晴');
    });

    test('跨年写完整年月日', () {
      final label = MemoLink.labelForMemo(
        content: '旧事',
        createdAt: DateTime(2025, 3, 12),
        now: now,
      );
      expect(label, '2025-03-12 旧事');
    });

    test('正文为空时只有日期', () {
      final label = MemoLink.labelForMemo(
        content: '',
        createdAt: DateTime(2026, 3, 12),
        now: now,
      );
      expect(label, '03-12');
    });

    test('正文里的方括号被清洗掉', () {
      final label = MemoLink.labelForMemo(
        content: '看[这里]',
        createdAt: DateTime(2026, 3, 12),
        now: now,
      );
      expect(label, isNot(contains('[')));
      expect(label, isNot(contains(']')));
    });

    test('正文首行是标签时不把 # 带进链接文字', () {
      final label = MemoLink.labelForMemo(
        content: '#随笔 今天下雨',
        createdAt: DateTime(2026, 3, 12),
        now: now,
      );
      expect(label, isNot(contains('#')));
    });
  });

  group('markdown', () {
    test('拼出完整的 Markdown 链接', () {
      expect(
        MemoLink.markdown(
          label: '03-12 深圳暴雨',
          kind: LinkKind.memo,
          remoteName: 'memos/123',
          localId: 45,
        ),
        '[03-12 深圳暴雨](islelog://memo/memos/123?lid=45)',
      );
    });

    test('标签里的方括号会被清洗，链接不会被撑破', () {
      final md = MemoLink.markdown(
        label: 'a[b]c',
        kind: LinkKind.memo,
        localId: 1,
      );
      expect(md, '[abc](islelog://memo?lid=1)');
    });
  });
}
