/// 内链选择器搜索框的输入解释。
///
/// 一个输入框同时承担"按日期找"和"按关键字找"：先按日期模式逐个匹配，
/// 全不命中才当关键字。零依赖纯函数模块。
library;

/// 搜索框输入的解释结果。
///
/// [start] 含端点、[end] 不含端点（半开区间）；两者要么都有要么都没有。
class LinkQuery {
  final DateTime? start;
  final DateTime? end;
  final String keyword;

  const LinkQuery._({this.start, this.end, this.keyword = ''});

  const LinkQuery.empty() : start = null, end = null, keyword = '';

  bool get isDate => start != null;
  bool get isKeyword => start == null && keyword.isNotEmpty;
  bool get isEmpty => start == null && keyword.isEmpty;
}

/// 把搜索框原始输入解释成日期区间或关键字。
LinkQuery parseLinkQuery(String raw, {DateTime? now}) {
  final text = raw.trim();
  if (text.isEmpty) return const LinkQuery.empty();

  final today = now ?? DateTime.now();

  // 相对日：今天 / 昨天 / 前天
  const relative = {'今天': 0, '昨天': -1, '前天': -2};
  final offset = relative[text];
  if (offset != null) {
    final day = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: offset));
    return _day(day);
  }

  // 年-月-日：2025-03-12 / 2025/3/12 / 2025年3月12日
  final ymd = RegExp(
    r'^(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})日?$',
  ).firstMatch(text);
  if (ymd != null) {
    final day = _validDate(
      int.parse(ymd.group(1)!),
      int.parse(ymd.group(2)!),
      int.parse(ymd.group(3)!),
    );
    if (day != null) return _day(day);
    return _keyword(text);
  }

  // 年-月：2025-03 / 2025年3月
  final ym = RegExp(r'^(\d{4})[-/年](\d{1,2})月?$').firstMatch(text);
  if (ym != null) {
    final year = int.parse(ym.group(1)!);
    final month = int.parse(ym.group(2)!);
    if (month >= 1 && month <= 12) {
      return LinkQuery._(
        start: DateTime(year, month, 1),
        end: DateTime(year, month + 1, 1),
      );
    }
    return _keyword(text);
  }

  // 月-日：3-12 / 03/12，按今年解释
  final md = RegExp(r'^(\d{1,2})[-/](\d{1,2})$').firstMatch(text);
  if (md != null) {
    final day = _validDate(
      today.year,
      int.parse(md.group(1)!),
      int.parse(md.group(2)!),
    );
    if (day != null) return _day(day);
    return _keyword(text);
  }

  // 单独的四位数字不当年份——它更可能是正文里的字。
  return _keyword(text);
}

LinkQuery _day(DateTime day) => LinkQuery._(
  start: DateTime(day.year, day.month, day.day),
  end: DateTime(day.year, day.month, day.day).add(const Duration(days: 1)),
);

LinkQuery _keyword(String text) => LinkQuery._(keyword: text);

/// 构造日期并验证没有被 DateTime 溢出修正（2 月 30 日会变成 3 月 2 日）。
DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}
