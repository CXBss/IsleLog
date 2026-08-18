import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/memo_detail/widgets/thread_nav_bar.dart';

Future<void> _pump(
  WidgetTester tester,
  ThreadNavData data, {
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  VoidCallback? onOpenThread,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        bottomNavigationBar: ThreadNavBar(
          data: data,
          onPrevious: onPrevious,
          onNext: onNext,
          onOpenThread: onOpenThread,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('展示事件串标题与当前位置', (tester) async {
    await _pump(
      tester,
      const ThreadNavData(
        threadTitle: '工位蛐蛐',
        position: 3,
        total: 4,
        hasPrevious: true,
        hasNext: true,
      ),
    );

    expect(find.text('「工位蛐蛐」3/4'), findsOneWidget);
  });

  testWidgets('首篇禁用上一篇', (tester) async {
    await _pump(
      tester,
      const ThreadNavData(
        threadTitle: '工位蛐蛐',
        position: 1,
        total: 4,
        hasPrevious: false,
        hasNext: true,
      ),
      onPrevious: () {},
      onNext: () {},
    );

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('thread_nav_previous')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('thread_nav_next')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('末篇禁用下一篇', (tester) async {
    await _pump(
      tester,
      const ThreadNavData(
        threadTitle: '工位蛐蛐',
        position: 4,
        total: 4,
        hasPrevious: true,
        hasNext: false,
      ),
      onPrevious: () {},
      onNext: () {},
    );

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('thread_nav_next')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('thread_nav_previous')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('只有一篇时前后都禁用', (tester) async {
    await _pump(
      tester,
      const ThreadNavData(
        threadTitle: '独篇事件',
        position: 1,
        total: 1,
        hasPrevious: false,
        hasNext: false,
      ),
      onPrevious: () {},
      onNext: () {},
    );

    for (final key in ['thread_nav_previous', 'thread_nav_next']) {
      expect(
        tester.widget<IconButton>(find.byKey(Key(key))).onPressed,
        isNull,
        reason: '$key 应为禁用态',
      );
    }
  });

  testWidgets('前后翻页与打开事件串各自触发回调', (tester) async {
    var previous = false, next = false, opened = false;

    await _pump(
      tester,
      const ThreadNavData(
        threadTitle: '工位蛐蛐',
        position: 2,
        total: 4,
        hasPrevious: true,
        hasNext: true,
      ),
      onPrevious: () => previous = true,
      onNext: () => next = true,
      onOpenThread: () => opened = true,
    );

    await tester.tap(find.byKey(const Key('thread_nav_previous')));
    await tester.tap(find.byKey(const Key('thread_nav_next')));
    await tester.tap(find.byKey(const Key('thread_nav_title')));
    await tester.pump();

    expect(previous, isTrue);
    expect(next, isTrue);
    expect(opened, isTrue);
  });
}
