import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/memo_editor/ai/polish_preview_page.dart';
import 'package:isle_log/services/ai/ai_models.dart';

const _segments = [
  AiPolishSegment(
    sourceIndexes: [0],
    originalText: '第一段。',
    revisedText: '第一段已润色。',
    reason: '语句通顺',
  ),
  AiPolishSegment(
    sourceIndexes: [1],
    originalText: '第二段。',
    revisedText: '第二段已润色。',
    reason: '表达简洁',
  ),
];

late String? result;

Future<void> _open(WidgetTester tester) async {
  result = null;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => const PolishPreviewPage(
                  original: '第一段。\n\n第二段。',
                  segments: _segments,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('使用 Diff 标记显示每个片段的修改', (tester) async {
    await _open(tester);

    expect(find.textContaining('已润色', findRichText: true), findsNWidgets(2));
    expect(find.text('语句通顺'), findsOneWidget);
    expect(find.text('表达简洁'), findsOneWidget);
  });

  testWidgets('初始不接受任何变更，应用所选返回原文', (tester) async {
    await _open(tester);

    await tester.tap(find.text('应用所选'));
    await tester.pumpAndSettle();
    expect(result, '第一段。\n\n第二段。');
  });

  testWidgets('全部接受后应用所选返回全部修订', (tester) async {
    await _open(tester);

    await tester.tap(find.text('全部接受'));
    await tester.tap(find.text('应用所选'));
    await tester.pumpAndSettle();
    expect(result, '第一段已润色。\n\n第二段已润色。');
  });

  testWidgets('逐段接受只应用对应段落', (tester) async {
    await _open(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用所选'));
    await tester.pumpAndSettle();
    expect(result, '第一段已润色。\n\n第二段。');
  });

  testWidgets('全部取消清除所有勾选', (tester) async {
    await _open(tester);

    await tester.tap(find.text('全部接受'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用所选'));
    await tester.pumpAndSettle();
    expect(result, '第一段。\n\n第二段。');
  });

  testWidgets('保护失败时禁用应用并显示原因', (tester) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => const PolishPreviewPage(
                    original: '记录 #工作',
                    segments: [
                      AiPolishSegment(
                        sourceIndexes: [0],
                        originalText: '记录 #工作',
                        revisedText: '记录 #生活',
                        reason: 'x',
                      ),
                    ],
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部接受'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用所选'));
    await tester.pumpAndSettle();

    expect(find.textContaining('受保护'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '应用所选'),
    );
    expect(button.onPressed, isNull);
    expect(result, isNull);

    // 取消勾选坏片段后错误清除、按钮恢复
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('受保护'), findsNothing);
    final recovered = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '应用所选'),
    );
    expect(recovered.onPressed, isNotNull);
  });
}
