import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/data/models/memo_entry.dart';
import 'package:isle_log/features/vault/widgets/vault_memo_card.dart';

MemoEntry _memo(String content, DateTime at, {List<String> tags = const []}) =>
    MemoEntry()
      ..content = content
      ..createdAt = at
      ..updatedAt = at
      ..tags = tags;

Future<void> _pump(
  WidgetTester tester,
  MemoEntry memo, {
  String query = '',
  VoidCallback? onLongPress,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: VaultMemoCard(
          memo: memo,
          query: query,
          onLongPress: onLongPress ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('展示正文与创建时间', (tester) async {
    await _pump(tester, _memo('今天去看海', DateTime(2026, 8, 11, 14, 30)));

    expect(find.textContaining('今天去看海'), findsOneWidget);
    // 旧实现只渲染一个裸 ListTile，连日期都不显示——这里钉住必须有时间
    expect(find.textContaining('2026-08-11'), findsOneWidget);
    expect(find.textContaining('14:30'), findsOneWidget);
  });

  testWidgets('标注为普通日记，与 vault 条目区分', (tester) async {
    await _pump(tester, _memo('普通', DateTime(2026, 8, 11)));
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
  });

  testWidgets('点击触发回调（查看全文）', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VaultMemoCard(
            memo: _memo('普通', DateTime(2026, 8, 11)),
            query: '',
            onLongPress: () {},
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(VaultMemoCard));
    expect(tapped, isTrue, reason: '此前只接了 onLongPress，点击无任何反应');
  });

  testWidgets('长正文按 6 行截断，不做字符数硬砍', (tester) async {
    // 一段远超 80 字符的中文，旧实现会砍到 80 字并加省略号
    final long = '今天去看海了。' * 40;
    await _pump(tester, _memo(long, DateTime(2026, 8, 11)));

    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(VaultMemoCard),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.data != null && w.data!.startsWith('今天去看海了'),
        ),
      ),
    );
    expect(text.maxLines, 6);
    expect(text.data, long, reason: '正文应完整传入，只靠 maxLines 截断显示');
  });

  testWidgets('长按触发回调（移入隐私空间）', (tester) async {
    var pressed = false;
    await _pump(
      tester,
      _memo('普通', DateTime(2026, 8, 11)),
      onLongPress: () => pressed = true,
    );

    await tester.longPress(find.byType(VaultMemoCard));
    expect(pressed, isTrue);
  });

  /// 递归收集 span 树里所有带文字的叶子节点。
  /// Text.rich 会把传入的 span 再包一层，所以不能只看顶层 children。
  List<TextSpan> leafSpans(InlineSpan span) {
    final result = <TextSpan>[];
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        if (s.text != null && s.text!.isNotEmpty) result.add(s);
        for (final child in s.children ?? const <InlineSpan>[]) {
          walk(child);
        }
      }
    }

    walk(span);
    return result;
  }

  testWidgets('命中的关键词片段被单独高亮', (tester) async {
    await _pump(tester, _memo('今天去看海了', DateTime(2026, 8, 11)), query: '海');

    final spans = tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((rt) => leafSpans(rt.text))
        .toList();

    final highlighted = spans.where(
      (s) => s.text == '海' && s.style?.backgroundColor != null,
    );
    expect(highlighted, hasLength(1), reason: '关键词应作为独立 span 并带高亮背景');

    // 其余部分仍完整保留，不能因高亮丢字
    final joined = spans.map((s) => s.text).join();
    expect(joined, contains('今天去看海了'));
  });

  testWidgets('无搜索词时不产生高亮片段', (tester) async {
    await _pump(tester, _memo('今天去看海了', DateTime(2026, 8, 11)));

    final spans = tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((rt) => leafSpans(rt.text))
        .toList();
    expect(spans.where((s) => s.style?.backgroundColor != null), isEmpty);
  });

  testWidgets('展示标签', (tester) async {
    await _pump(
      tester,
      _memo('带标签', DateTime(2026, 8, 11), tags: ['心情', '旅行']),
    );
    expect(find.textContaining('心情'), findsOneWidget);
    expect(find.textContaining('旅行'), findsOneWidget);
  });
}
