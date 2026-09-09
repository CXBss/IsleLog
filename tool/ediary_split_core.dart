/// 一次性拆分脚本的纯逻辑：把用 `||` 连接的多段日记切开，为每段算出 createTime。
/// 零副作用，可单测。主入口见 `tool/split_ediary.dart`。
library;

import 'ediary_clean_core.dart' show extractTagsLike;

const kEdiaryTag = 'eDiary日记';

/// 可选的日期前缀：`YYYY年M月D日` / `YYYY-M-D` / `YYYY/M/D`，后跟空白。
final RegExp _datePrefix = RegExp(
  r'^\d{4}\s*(?:年|-|/)\s*\d{1,2}\s*(?:月|-|/)\s*\d{1,2}(?:\s*日)?[ T\s]*',
);
/// 可选的时段词。
final RegExp _meridiem = RegExp(r'^(上午|下午|凌晨|早上|晚上|中午|傍晚|夜里)\s*');
/// 时间本体：HH:MM 或 HH:MM:SS，后面不能紧跟字母/数字/冒号（挡掉 11:00p.m）。
final RegExp _time = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?(?![\w:])');

/// 段首第一行若以时间戳开头，返回当天的「时分秒」；否则 null。
/// 日期部分（若有）一律忽略——按用户要求日期永远取原日记的日期。
/// 认得：`HH:MM[:SS]`、`YYYY-MM-DD HH:MM[:SS]`、`YYYY年M月D日HH:MM[:SS]`，
/// 以及带 `上午/下午/中午…` 的变体；全角冒号 `：` 归一为半角。
({int h, int m, int s})? parseLeadingTime(String segment) {
  var s = segment
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (s.isEmpty) return null;
  s = s.replaceAll('：', ':');

  s = s.replaceFirst(_datePrefix, '');
  final mer = _meridiem.firstMatch(s);
  if (mer != null) s = s.substring(mer.end);
  final t = _time.firstMatch(s);
  if (t == null) return null;

  var h = int.parse(t[1]!);
  final min = int.parse(t[2]!);
  final sec = t[3] != null ? int.parse(t[3]!) : 0;

  switch (mer?.group(1)) {
    case '下午' || '晚上' || '傍晚' || '夜里':
      if (h < 12) h += 12;
    case '上午' || '早上' || '凌晨':
      if (h == 12) h = 0;
    default:
      break; // 中午 / 无：原样
  }
  return _valid(h, min, sec);
}

({int h, int m, int s})? _valid(int h, int m, int s) {
  if (h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) return null;
  return (h: h, m: m, s: s);
}

/// 按 `||` 切段，去掉首尾空白，丢弃「空段」或「只剩 #eDiary日记 的段」。
List<String> splitSegments(String content) {
  return content
      .split('||')
      .map((s) => s.replaceAll(RegExp(r'^\s+'), '').replaceAll(RegExp(r'\s+$'), ''))
      .where((s) {
        final withoutTag = s
            .replaceAll('#$kEdiaryTag', '')
            .replaceAll(RegExp(r'\s'), '');
        return withoutTag.isNotEmpty;
      })
      .toList();
}

/// 为每段算 createTime。
/// - 第 0 段 = 原日记 createdAt（不变）
/// - 其余段：段首有时间戳 → 原日期 + 该时间；否则 = 上一段 + 1 分钟
///   （+1 分钟若跨过当天 23:59:59 则不加，与上一段同一时刻）
List<DateTime> computeSegmentTimes(
  DateTime originalCreatedAt,
  List<String> segments,
) {
  final out = <DateTime>[originalCreatedAt];
  var prev = originalCreatedAt;
  for (var i = 1; i < segments.length; i++) {
    final t = parseLeadingTime(segments[i]);
    DateTime cur;
    if (t != null) {
      cur = DateTime(
        originalCreatedAt.year,
        originalCreatedAt.month,
        originalCreatedAt.day,
        t.h,
        t.m,
        t.s,
      );
    } else {
      final candidate = prev.add(const Duration(minutes: 1));
      cur = candidate.day == originalCreatedAt.day &&
              candidate.month == originalCreatedAt.month &&
              candidate.year == originalCreatedAt.year
          ? candidate
          : prev;
    }
    out.add(cur);
    prev = cur;
  }
  return out;
}

/// 段落正文：末尾确保带 #eDiary日记（已含则不动，原文其余部分逐字保留）。
String buildSegmentContent(String segment) {
  final trimmed = segment.replaceAll(RegExp(r'\s+$'), '');
  if (extractTagsLike(trimmed).contains(kEdiaryTag)) return trimmed;
  return '$trimmed\n\n#$kEdiaryTag';
}
