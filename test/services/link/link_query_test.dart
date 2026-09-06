import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/services/link/link_query.dart';

void main() {
  final now = DateTime(2026, 9, 6, 15, 30);

  group('日期识别', () {
    test('月-日 按今年解释', () {
      final q = parseLinkQuery('3-12', now: now);
      expect(q.isDate, isTrue);
      expect(q.start, DateTime(2026, 3, 12));
      expect(q.end, DateTime(2026, 3, 13));
    });

    test('月/日 与月-日 等价', () {
      expect(parseLinkQuery('3/12', now: now).start, DateTime(2026, 3, 12));
    });

    test('补零写法同样识别', () {
      expect(parseLinkQuery('03-12', now: now).start, DateTime(2026, 3, 12));
    });

    test('完整年月日', () {
      final q = parseLinkQuery('2025-03-12', now: now);
      expect(q.start, DateTime(2025, 3, 12));
      expect(q.end, DateTime(2025, 3, 13));
    });

    test('斜杠写法的年月日', () {
      expect(parseLinkQuery('2025/3/12', now: now).start, DateTime(2025, 3, 12));
    });

    test('中文年月日', () {
      expect(
        parseLinkQuery('2025年3月12日', now: now).start,
        DateTime(2025, 3, 12),
      );
    });

    test('年-月 覆盖整月', () {
      final q = parseLinkQuery('2025-03', now: now);
      expect(q.start, DateTime(2025, 3, 1));
      expect(q.end, DateTime(2025, 4, 1));
    });

    test('十二月的整月区间跨到次年一月', () {
      final q = parseLinkQuery('2025-12', now: now);
      expect(q.start, DateTime(2025, 12, 1));
      expect(q.end, DateTime(2026, 1, 1));
    });

    test('中文年月', () {
      expect(parseLinkQuery('2025年3月', now: now).start, DateTime(2025, 3, 1));
    });

    test('今天', () {
      final q = parseLinkQuery('今天', now: now);
      expect(q.start, DateTime(2026, 9, 6));
      expect(q.end, DateTime(2026, 9, 7));
    });

    test('昨天', () {
      expect(parseLinkQuery('昨天', now: now).start, DateTime(2026, 9, 5));
    });

    test('前天', () {
      expect(parseLinkQuery('前天', now: now).start, DateTime(2026, 9, 4));
    });

    test('首尾空格不影响识别', () {
      expect(parseLinkQuery('  3-12  ', now: now).start, DateTime(2026, 3, 12));
    });
  });

  group('关键字', () {
    test('单独四位数字当关键字，不当年份', () {
      final q = parseLinkQuery('2025', now: now);
      expect(q.isDate, isFalse);
      expect(q.keyword, '2025');
    });

    test('普通文字是关键字', () {
      final q = parseLinkQuery('深圳暴雨', now: now);
      expect(q.isKeyword, isTrue);
      expect(q.keyword, '深圳暴雨');
    });

    test('月份越界时退化为关键字', () {
      expect(parseLinkQuery('13-45', now: now).isKeyword, isTrue);
    });

    test('日期越界时退化为关键字', () {
      expect(parseLinkQuery('2025-02-30', now: now).isKeyword, isTrue);
    });

    test('关键字去掉首尾空格', () {
      expect(parseLinkQuery('  暴雨 ', now: now).keyword, '暴雨');
    });
  });

  group('空输入', () {
    test('空串既不是日期也不是关键字', () {
      final q = parseLinkQuery('', now: now);
      expect(q.isEmpty, isTrue);
      expect(q.isDate, isFalse);
      expect(q.isKeyword, isFalse);
    });

    test('纯空格等同空串', () {
      expect(parseLinkQuery('   ', now: now).isEmpty, isTrue);
    });
  });
}
