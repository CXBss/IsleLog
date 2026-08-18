import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/threads/widgets/thread_card.dart';

Future<void> _pump(
  WidgetTester tester,
  ThreadCardData data, {
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ThreadCard(data: data, onTap: onTap))),
  );
}

void main() {
  testWidgets('展示标题、简介与篇数日期跨度', (tester) async {
    await _pump(
      tester,
      ThreadCardData(
        title: '工位蛐蛐',
        summary: '找了两晚没找到，第三晚又听到了',
        memberCount: 4,
        startedAt: DateTime(2026, 8, 11),
        lastAt: DateTime(2026, 8, 13),
      ),
    );

    expect(find.text('工位蛐蛐'), findsOneWidget);
    expect(find.text('找了两晚没找到，第三晚又听到了'), findsOneWidget);
    expect(find.text('4 篇 · 08月11日–08月13日'), findsOneWidget);
  });

  testWidgets('同一天的事件串只显示一个日期', (tester) async {
    await _pump(
      tester,
      ThreadCardData(
        title: '单日事件',
        summary: '',
        memberCount: 1,
        startedAt: DateTime(2026, 8, 11),
        lastAt: DateTime(2026, 8, 11),
      ),
    );

    expect(find.text('1 篇 · 08月11日'), findsOneWidget);
  });

  testWidgets('无成员时不显示日期跨度', (tester) async {
    await _pump(
      tester,
      const ThreadCardData(
        title: '空事件串',
        summary: '',
        memberCount: 0,
        startedAt: null,
        lastAt: null,
      ),
    );

    expect(find.text('0 篇'), findsOneWidget);
    expect(find.textContaining('月'), findsNothing);
  });

  testWidgets('简介为空时不渲染简介行', (tester) async {
    await _pump(
      tester,
      const ThreadCardData(
        title: '无简介',
        summary: '',
        memberCount: 2,
        startedAt: null,
        lastAt: null,
      ),
    );

    expect(find.byKey(const Key('thread_card_summary')), findsNothing);
  });

  testWidgets('简介存在时渲染简介行', (tester) async {
    await _pump(
      tester,
      const ThreadCardData(
        title: '有简介',
        summary: '一句话进展',
        memberCount: 2,
        startedAt: null,
        lastAt: null,
      ),
    );

    expect(find.byKey(const Key('thread_card_summary')), findsOneWidget);
  });

  testWidgets('点击卡片触发回调', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      const ThreadCardData(
        title: '可点击',
        summary: '',
        memberCount: 0,
        startedAt: null,
        lastAt: null,
      ),
      onTap: () => tapped = true,
    );

    await tester.tap(find.byType(ThreadCard));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
