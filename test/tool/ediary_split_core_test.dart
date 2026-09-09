import 'package:flutter_test/flutter_test.dart';

import '../../tool/ediary_split_core.dart';

void main() {
  group('parseLeadingTime', () {
    test('HH:MM:SS 段首', () {
      expect(parseLeadingTime('20:15:56\n最近没啥事了'), (h: 20, m: 15, s: 56));
    });

    test('HH:MM 段首（补秒 0）', () {
      expect(parseLeadingTime('8:30 起床'), (h: 8, m: 30, s: 0));
      expect(parseLeadingTime('17:25 下楼'), (h: 17, m: 25, s: 0));
    });

    test('YYYY-MM-DD HH:MM:SS 只取时间部分，日期忽略', () {
      expect(parseLeadingTime('2025-04-09 22:36:56\n今天'), (h: 22, m: 36, s: 56));
      expect(parseLeadingTime('2025-07-06T19:54:10 傍晚'), (h: 19, m: 54, s: 10));
    });

    test('中文日期前缀 + 时间（无空格）', () {
      expect(parseLeadingTime('2021年2月4日20:18:21'), (h: 20, m: 18, s: 21));
      expect(parseLeadingTime('2025年3月9日 20:46:16\n文'), (h: 20, m: 46, s: 16));
    });

    test('上午/下午 变体', () {
      expect(parseLeadingTime('2025-09-01 上午09:45'), (h: 9, m: 45, s: 0));
      expect(parseLeadingTime('2023-01-31 下午09:12'), (h: 21, m: 12, s: 0));
      expect(parseLeadingTime('下午2:30 出门'), (h: 14, m: 30, s: 0));
      expect(parseLeadingTime('上午12:05'), (h: 0, m: 5, s: 0)); // 12am → 0
      expect(parseLeadingTime('中午12:00'), (h: 12, m: 0, s: 0)); // 中午不调整
      expect(parseLeadingTime('下午12:20'), (h: 12, m: 20, s: 0)); // 12pm 保持 12
    });

    test('全角冒号归一', () {
      expect(parseLeadingTime('20：18：21 记录'), (h: 20, m: 18, s: 21));
    });

    test('只有日期没有时间 → null', () {
      expect(parseLeadingTime('2021年2月4日'), isNull);
    });

    test('跳过段首空行', () {
      expect(parseLeadingTime('\n\n  \n17:58:26\n昨天晚上'), (h: 17, m: 58, s: 26));
    });

    test('11:00p.m 之类不算时间戳', () {
      expect(parseLeadingTime('11:00p.m-12:30p.m 我在 cctv6'), isNull);
    });

    test('点号形式 14.04 不算', () {
      expect(parseLeadingTime('14.04\n晴'), isNull);
    });

    test('非法时间不算', () {
      expect(parseLeadingTime('25:99:99 xxx'), isNull);
      expect(parseLeadingTime('12:60 xxx'), isNull);
    });

    test('纯文字段首返回 null', () {
      expect(parseLeadingTime('在老家我又看《傲世九重天》了'), isNull);
      expect(parseLeadingTime('**# 投了空天院简历**'), isNull);
    });
  });

  group('splitSegments', () {
    test('多段切开', () {
      expect(splitSegments('a||b||c'), ['a', 'b', 'c']);
    });

    test('尾部只剩标签的段丢弃（末尾孤立 ||）', () {
      expect(splitSegments('正文内容。||\n\n#eDiary日记'), ['正文内容。']);
    });

    test('空段丢弃', () {
      expect(splitSegments('a|| ||b'), ['a', 'b']);
    });

    test('无 || 原样单段', () {
      expect(splitSegments('没有分隔符的日记'), ['没有分隔符的日记']);
    });

    test('保留含真实内容 + 标签的末段', () {
      expect(
        splitSegments('第一段。||第二段。\n\n#eDiary日记'),
        ['第一段。', '第二段。\n\n#eDiary日记'],
      );
    });
  });

  group('computeSegmentTimes', () {
    final orig = DateTime(2014, 2, 12, 16, 40, 0);

    test('无时间戳逐段 +1 分钟', () {
      final t = computeSegmentTimes(orig, ['s0', 's1', 's2']);
      expect(t, [
        DateTime(2014, 2, 12, 16, 40, 0),
        DateTime(2014, 2, 12, 16, 41, 0),
        DateTime(2014, 2, 12, 16, 42, 0),
      ]);
    });

    test('段首时间戳用当天该时间，日期不变', () {
      final t = computeSegmentTimes(orig, ['s0', '20:15:56\n文本']);
      expect(t[1], DateTime(2014, 2, 12, 20, 15, 56));
    });

    test('时间戳段之后的无戳段从它 +1 分钟累进', () {
      final t = computeSegmentTimes(orig, ['s0', '10:00:00 a', 'b', 'c']);
      expect(t, [
        DateTime(2014, 2, 12, 16, 40, 0),
        DateTime(2014, 2, 12, 10, 0, 0),
        DateTime(2014, 2, 12, 10, 1, 0),
        DateTime(2014, 2, 12, 10, 2, 0),
      ]);
    });

    test('+1 分钟跨天则不加，与上一段同一时刻', () {
      final o = DateTime(2014, 2, 12, 23, 58, 0);
      final t = computeSegmentTimes(o, ['s0', 'x', 'y', 'z']);
      expect(t, [
        DateTime(2014, 2, 12, 23, 58, 0),
        DateTime(2014, 2, 12, 23, 59, 0),
        DateTime(2014, 2, 12, 23, 59, 0),
        DateTime(2014, 2, 12, 23, 59, 0),
      ]);
    });

    test('full datetime 段首也只改时间不改日期', () {
      final t = computeSegmentTimes(orig, ['s0', '2025-04-09 22:36:56\n文']);
      expect(t[1], DateTime(2014, 2, 12, 22, 36, 56));
    });
  });

  group('buildSegmentContent', () {
    test('无标签的段末尾补 #eDiary日记', () {
      expect(buildSegmentContent('几天前我们回来了。'), '几天前我们回来了。\n\n#eDiary日记');
    });

    test('已含标签的段不重复加', () {
      expect(
        buildSegmentContent('最后一段。\n\n#eDiary日记'),
        '最后一段。\n\n#eDiary日记',
      );
    });

    test('段内有其它 #标签 仍补 eDiary日记', () {
      expect(
        buildSegmentContent('聊到 #大事件 的事'),
        '聊到 #大事件 的事\n\n#eDiary日记',
      );
    });

    test('去掉尾部多余空白再补标签', () {
      expect(buildSegmentContent('正文。\n\n\n'), '正文。\n\n#eDiary日记');
    });
  });
}
