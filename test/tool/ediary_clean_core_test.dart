import 'package:flutter_test/flutter_test.dart';

import '../../tool/ediary_clean_core.dart';

void main() {
  group('cleanEdiaryContent — 数字实体', () {
    test('用户样例：&#50;021 → 2021，标签与其它 Markdown 不动', () {
      const input = '**&#50;021年4月1日 星期四 20:37**\n'
          '\n'
          '**日记**\n'
          '\n'
          '正文一句话 #ediary日记';
      const expected = '**2021年4月1日 星期四 20:37**\n'
          '\n'
          '**日记**\n'
          '\n'
          '正文一句话 #ediary日记';
      expect(cleanEdiaryContent(input), expected);
    });

    test('十六进制实体 &#x32; → 2', () {
      expect(cleanEdiaryContent('a&#x32;b'), 'a2b');
      expect(cleanEdiaryContent('a&#X32;b'), 'a2b');
    });

    test('&#39; → 单引号', () {
      expect(cleanEdiaryContent("it&#39;s"), "it's");
    });

    test('非法码点原样保留', () {
      expect(cleanEdiaryContent('&#1114112;'), '&#1114112;');
    });
  });

  group('cleanEdiaryContent — 命名实体', () {
    test('基本 XML 实体', () {
      expect(
        cleanEdiaryContent('a &lt;b&gt; &quot;c&quot; &apos;d&apos;'),
        'a <b> "c" \'d\'',
      );
    });

    test('&amp; 单次解码，不吃掉后续实体', () {
      expect(cleanEdiaryContent('a &amp;#50; b'), 'a &#50; b');
      expect(cleanEdiaryContent('Tom &amp; Jerry'), 'Tom & Jerry');
    });

    test('排版类实体', () {
      expect(cleanEdiaryContent('3&mdash;5'), '3—5');
      expect(cleanEdiaryContent('等等&hellip;'), '等等…');
    });

    test('未知命名实体原样保留', () {
      expect(cleanEdiaryContent('&foobar;'), '&foobar;');
    });
  });

  group('cleanEdiaryContent — &nbsp;', () {
    test('独占一行的 &nbsp; 变成空行', () {
      const input = 'A\n&nbsp;\nB';
      expect(cleanEdiaryContent(input), 'A\n\nB');
    });

    test('多个 &nbsp; 独占一行也变成空行', () {
      const input = 'A\n&nbsp; &nbsp;&nbsp;\nB';
      expect(cleanEdiaryContent(input), 'A\n\nB');
    });

    test('行内 &nbsp; 序列折叠为一个普通空格', () {
      expect(cleanEdiaryContent('甲&nbsp;&nbsp;乙'), '甲 乙');
      expect(cleanEdiaryContent('甲&nbsp;乙'), '甲 乙');
    });
  });

  group('cleanEdiaryContent — 残留 HTML 标签', () {
    test('<br> 及其变体 → 换行', () {
      expect(cleanEdiaryContent('a<br>b<br/>c<br />d'), 'a\nb\nc\nd');
      expect(cleanEdiaryContent('a<BR>b'), 'a\nb');
    });

    test('<div>/<p> 闭合标签 → 换行，开标签删除', () {
      expect(cleanEdiaryContent('<div>甲</div><div>乙</div>'), '甲\n乙');
      expect(cleanEdiaryContent('<p>段落</p>'), '段落');
    });

    test('带属性的 span/font 被剥掉，保留内部文字', () {
      expect(
        cleanEdiaryContent('<span style="color:red">红字</span>'),
        '红字',
      );
      expect(
        cleanEdiaryContent('<font color="#ff0000" size="3">大红</font>'),
        '大红',
      );
    });

    test('内联强调标签被剥掉', () {
      expect(cleanEdiaryContent('<b>粗</b><i>斜</i><strong>重</strong>'), '粗斜重');
    });

    test('非白名单里的尖括号文本保留', () {
      expect(cleanEdiaryContent('若 a<c 且 b>c'), '若 a<c 且 b>c');
      expect(cleanEdiaryContent('泛型 List<T> 用法'), '泛型 List<T> 用法');
      expect(cleanEdiaryContent('<unknown>保留</unknown>'), '<unknown>保留</unknown>');
    });
  });

  group('cleanEdiaryContent — 反斜杠转义', () {
    test(r'行首 \# 标题 → # 标题（还原成 Markdown 标题）', () {
      expect(cleanEdiaryContent(r'\# 奶奶去世过程'), '# 奶奶去世过程');
      expect(cleanEdiaryContent(r'正文' '\n' r'\# 小节' '\n' r'更多'),
          '正文\n# 小节\n更多');
    });

    test(r'**\# 标题** 里的 \# 也还原', () {
      expect(cleanEdiaryContent(r'**\# 起床和安装监控**'), '**# 起床和安装监控**');
    });

    test(r'漏空格的 \#关于空调 补空格，行首不会被当成标签', () {
      expect(cleanEdiaryContent(r'\#上海封城期间的事'), '# 上海封城期间的事');
      expect(cleanEdiaryContent(r'**\#关于空调**'), '**# 关于空调**');
      expect(extractTagsLike(cleanEdiaryContent(r'\#上海封城期间的事')), isEmpty);
    });

    test(r'\* \_ \> \- 等其它转义保持不动', () {
      expect(cleanEdiaryContent(r'a\*b\_c\>d\-e'), r'a\*b\_c\>d\-e');
    });

    test(r'段末 \|\| → ||（只去反斜杠）', () {
      expect(cleanEdiaryContent(r'今天很累。\|\|'), '今天很累。||');
      expect(cleanEdiaryContent(r'a\|b'), 'a|b');
    });
  });

  group('cleanEdiaryContent — 空白收敛', () {
    test('3 个以上连续空行收敛为 1 个空行', () {
      expect(cleanEdiaryContent('A\n\n\n\n\nB'), 'A\n\nB');
    });

    test('保留单个空行（段落间距）', () {
      expect(cleanEdiaryContent('A\n\nB'), 'A\n\nB');
    });

    test('行尾空白清除', () {
      expect(cleanEdiaryContent('A   \nB\t\n'), 'A\nB');
    });

    test('首尾空行清除', () {
      expect(cleanEdiaryContent('\n\n正文\n\n'), '正文');
    });
  });

  group('cleanEdiaryContent — 组合与幂等', () {
    test('实体+nbsp+标签+空行的混合样例', () {
      const input = '<div>**&#50;021年4月1日**</div>\n'
          '&nbsp;\n'
          '\n'
          '<span>心情：&quot;平静&quot;</span><br>\n'
          '\n'
          '\n'
          '正文&nbsp;&nbsp;结尾 #ediary日记\n';
      const expected = '**2021年4月1日**\n'
          '\n'
          '心情："平静"\n'
          '\n'
          '正文 结尾 #ediary日记';
      expect(cleanEdiaryContent(input), expected);
    });

    test('干净文本保持不变（幂等）', () {
      const clean = '# 标题\n\n一段正文，带 #ediary日记 标签。\n\n- [ ] 待办\n- [x] 完成';
      expect(cleanEdiaryContent(clean), clean);
      expect(cleanEdiaryContent(cleanEdiaryContent(clean)), clean);
    });

    test('对已清洗结果再跑一次不再变化', () {
      const input = '<div>甲</div>\n&nbsp;\n\n\n<b>乙</b>&amp;丙';
      final once = cleanEdiaryContent(input);
      expect(cleanEdiaryContent(once), once);
    });
  });
}
