import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/data/models/vault_entry.dart';
import 'package:isle_log/features/vault/vault_browse_model.dart';

MemoEntry _memo(String content, DateTime at, {List<String> tags = const []}) =>
    MemoEntry()
      ..content = content
      ..createdAt = at
      ..updatedAt = at
      ..tags = tags;

VaultEntry _vault(
  String content,
  DateTime at, {
  List<String> tags = const [],
}) => VaultEntry(
  id: content,
  content: content,
  createdAt: at,
  updatedAt: at,
  tags: tags,
  attachmentIds: const [],
);

void main() {
  final d10 = DateTime(2026, 8, 10, 9);
  final d11a = DateTime(2026, 8, 11, 8);
  final d11b = DateTime(2026, 8, 11, 20);
  final d12 = DateTime(2026, 9, 12, 9);

  group('scope 过滤', () {
    test('all 同时包含主库和 vault 条目', () {
      final items = VaultBrowseModel.apply(
        memos: [_memo('普通', d10)],
        entries: [_vault('隐私', d11a)],
        filter: const VaultBrowseFilter(),
      );
      expect(items.length, 2);
    });

    test('vaultOnly 只保留 vault 条目', () {
      final items = VaultBrowseModel.apply(
        memos: [_memo('普通', d10)],
        entries: [_vault('隐私', d11a)],
        filter: const VaultBrowseFilter(scope: VaultScope.vaultOnly),
      );
      expect(items.length, 1);
      expect(items.single.isVault, isTrue);
    });
  });

  test('结果按时间倒序', () {
    final items = VaultBrowseModel.apply(
      memos: [_memo('早', d10), _memo('晚', d12)],
      entries: [_vault('中', d11a)],
      filter: const VaultBrowseFilter(),
    );
    expect(items.map((e) => e.content).toList(), ['晚', '中', '早']);
  });

  group('搜索', () {
    test('同时匹配主库和 vault 的正文', () {
      final items = VaultBrowseModel.apply(
        memos: [_memo('去看海了', d10), _memo('吃饭', d11a)],
        entries: [_vault('海边的秘密', d11b)],
        filter: const VaultBrowseFilter(query: '海'),
      );
      expect(items.map((e) => e.content).toList(), ['海边的秘密', '去看海了']);
    });

    test('大小写不敏感', () {
      final items = VaultBrowseModel.apply(
        memos: [_memo('Hello World', d10)],
        entries: const [],
        filter: const VaultBrowseFilter(query: 'hello'),
      );
      expect(items.length, 1);
    });

    test('空白查询不过滤', () {
      final items = VaultBrowseModel.apply(
        memos: [_memo('a', d10)],
        entries: const [],
        filter: const VaultBrowseFilter(query: '   '),
      );
      expect(items.length, 1);
    });
  });

  group('按天筛选', () {
    test('只保留指定当天的条目，忽略时分', () {
      final items = VaultBrowseModel.apply(
        memos: [_memo('10 号', d10), _memo('11 号早', d11a)],
        entries: [_vault('11 号晚', d11b)],
        filter: VaultBrowseFilter(day: DateTime(2026, 8, 11, 23, 59)),
      );
      expect(items.map((e) => e.content).toList(), ['11 号晚', '11 号早']);
    });
  });

  group('标签筛选', () {
    test('按标签过滤，主库和 vault 都参与', () {
      final items = VaultBrowseModel.apply(
        memos: [
          _memo('带心情', d10, tags: ['心情']),
          _memo('不带', d11a, tags: ['工作']),
        ],
        entries: [
          _vault('隐私带心情', d11b, tags: ['心情']),
        ],
        filter: const VaultBrowseFilter(tag: '心情'),
      );
      expect(items.map((e) => e.content).toList(), ['隐私带心情', '带心情']);
    });
  });

  test('搜索 / 日期 / 标签 / scope 可叠加', () {
    final items = VaultBrowseModel.apply(
      memos: [
        _memo('海 11号 心情', d11a, tags: ['心情']),
        _memo('海 10号 心情', d10, tags: ['心情']),
      ],
      entries: [
        _vault('海 11号 隐私 心情', d11b, tags: ['心情']),
        _vault('山 11号 隐私 心情', d11b, tags: ['心情']),
      ],
      filter: VaultBrowseFilter(
        query: '海',
        day: DateTime(2026, 8, 11),
        tag: '心情',
        scope: VaultScope.vaultOnly,
      ),
    );
    expect(items.map((e) => e.content).toList(), ['海 11号 隐私 心情']);
  });

  group('按天分组', () {
    test('同一天归为一组，组按日期倒序，组内按时间倒序', () {
      final items = VaultBrowseModel.apply(
        memos: [_memo('11 号早', d11a), _memo('10 号', d10)],
        entries: [_vault('11 号晚', d11b)],
        filter: const VaultBrowseFilter(),
      );
      final groups = VaultBrowseModel.groupByDay(items);

      expect(groups.length, 2);
      expect(groups[0].$1, '2026-08-11');
      expect(groups[0].$2.map((e) => e.content).toList(), ['11 号晚', '11 号早']);
      expect(groups[1].$1, '2026-08-10');
    });

    test('空列表返回空分组', () {
      expect(VaultBrowseModel.groupByDay(const []), isEmpty);
    });
  });

  group('标签统计', () {
    test('合并主库与 vault 的标签计数', () {
      final counts = VaultBrowseModel.tagCounts(
        memos: [
          _memo('a', d10, tags: ['心情', '工作']),
        ],
        entries: [
          _vault('b', d11a, tags: ['心情']),
        ],
        scope: VaultScope.all,
      );
      expect(counts['心情'], 2);
      expect(counts['工作'], 1);
    });

    test('vaultOnly 时不统计主库标签', () {
      final counts = VaultBrowseModel.tagCounts(
        memos: [
          _memo('a', d10, tags: ['工作']),
        ],
        entries: [
          _vault('b', d11a, tags: ['心情']),
        ],
        scope: VaultScope.vaultOnly,
      );
      expect(counts.containsKey('工作'), isFalse);
      expect(counts['心情'], 1);
    });
  });

  group('月度有记录的日期', () {
    test('返回当月有条目的日号，合并两个来源', () {
      final days = VaultBrowseModel.daysWithEntriesInMonth(
        memos: [_memo('a', d10)],
        entries: [_vault('b', d11a)],
        scope: VaultScope.all,
        year: 2026,
        month: 8,
      );
      expect(days, {10, 11});
    });

    test('不包含其他月份', () {
      final days = VaultBrowseModel.daysWithEntriesInMonth(
        memos: [_memo('九月', d12)],
        entries: const [],
        scope: VaultScope.all,
        year: 2026,
        month: 8,
      );
      expect(days, isEmpty);
    });
  });
}
