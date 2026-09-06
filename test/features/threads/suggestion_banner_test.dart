import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/threads/widgets/suggestion_banner.dart';

const _items = [
  SuggestionItem(
    suggestionLocalKey: '1',
    memoSnippet: '今晚又听到蛐蛐了',
    threadTitle: '工位蛐蛐',
    reason: '同样在讲工位的蛐蛐',
  ),
  SuggestionItem(
    suggestionLocalKey: '2',
    memoSnippet: '装了新灯',
    threadTitle: '装修',
    reason: '同一轮装修',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<SuggestionItem> items = _items,
  void Function(int)? onAccept,
  void Function(int)? onDismiss,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SuggestionBanner(
          items: items,
          onAccept: onAccept ?? (_) {},
          onDismiss: onDismiss ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('显示条数与每条的日记摘要和事件串', (tester) async {
    await _pump(tester);

    expect(find.text('发现 2 条可能的关联'), findsOneWidget);
    expect(find.text('今晚又听到蛐蛐了'), findsOneWidget);
    expect(find.textContaining('工位蛐蛐'), findsWidgets);
    expect(find.text('同样在讲工位的蛐蛐'), findsOneWidget);
  });

  testWidgets('无建议时不渲染', (tester) async {
    await _pump(tester, items: const []);

    expect(find.textContaining('发现'), findsNothing);
  });

  testWidgets('加入与忽略各自回调对应的索引', (tester) async {
    int? accepted;
    int? dismissed;
    await _pump(
      tester,
      onAccept: (index) => accepted = index,
      onDismiss: (index) => dismissed = index,
    );

    await tester.tap(find.byKey(const Key('suggestion_accept_1')));
    await tester.tap(find.byKey(const Key('suggestion_dismiss_0')));
    await tester.pump();

    expect(accepted, 1);
    expect(dismissed, 0);
  });
}
