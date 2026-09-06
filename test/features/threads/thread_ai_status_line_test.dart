import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/threads/widgets/thread_ai_status_line.dart';

Future<void> _pump(WidgetTester tester, ThreadAiStatusData data) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ThreadAiStatusLine(data: data))),
  );
}

void main() {
  testWidgets('待分析时显示数量与处理时间', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: true,
        providerAvailable: true,
        pendingMemos: 3,
        dirtyThreads: 1,
      ),
    );

    expect(find.text('3 篇待分析 · 今晚 4:00 处理'), findsOneWidget);
  });

  testWidgets('模型离线时明确提示', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: true,
        providerAvailable: false,
        pendingMemos: 3,
        dirtyThreads: 0,
      ),
    );

    expect(find.text('模型离线，暂停分析'), findsOneWidget);
  });

  testWidgets('关闭自动分析时提示已关闭', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: false,
        providerAvailable: true,
        pendingMemos: 5,
        dirtyThreads: 0,
      ),
    );

    expect(find.text('自动分析已关闭'), findsOneWidget);
  });

  // 空闲时整行不占位，避免常驻噪音
  testWidgets('无待处理项时不渲染任何内容', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: true,
        providerAvailable: true,
        pendingMemos: 0,
        dirtyThreads: 0,
      ),
    );

    expect(find.byType(Text), findsNothing);
  });
}
