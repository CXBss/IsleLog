import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isle_log/features/threads/widgets/thread_ai_status_line.dart';

Future<void> _pump(WidgetTester tester, ThreadAiStatusData data) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ThreadAiStatusLine(data: data))),
  );
}

void main() {
  testWidgets('仅有待分析日记时显示数量与处理时间', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: true,
        providerAvailable: true,
        pendingMemos: 3,
        dirtyThreads: 0,
      ),
    );

    expect(find.text('3 篇待分析 · 今晚 4:00 处理'), findsOneWidget);
  });

  testWidgets('待分析日记与简介待更新同时存在时两者都展示', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: true,
        providerAvailable: true,
        pendingMemos: 3,
        dirtyThreads: 1,
      ),
    );

    expect(find.text('3 篇待分析 · 1 条简介待更新 · 今晚 4:00 处理'), findsOneWidget);
  });

  // 手动把日记加入事件串只置 summary_dirty，不动 pendingMemos，
  // 是最常见操作后的日常状态，不该被文案误读成「0 篇待分析」
  testWidgets('只有简介待更新、没有待分析日记时单独展示简介待更新', (tester) async {
    await _pump(
      tester,
      const ThreadAiStatusData(
        enabled: true,
        providerAvailable: true,
        pendingMemos: 0,
        dirtyThreads: 2,
      ),
    );

    expect(find.text('2 条简介待更新 · 今晚 4:00 处理'), findsOneWidget);
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
