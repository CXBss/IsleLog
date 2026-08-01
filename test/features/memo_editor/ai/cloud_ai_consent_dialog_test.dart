import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/memo_editor/ai/cloud_ai_consent_dialog.dart';

void main() {
  testWidgets('显示 Provider、模型、记录数、字符数、附加信息和仅本次允许', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showCloudAiConsentDialog(
                context: context,
                model: 'deepseek-chat',
                recordCount: 1,
                characterCount: 256,
                contentModeLabel: '原文',
                includedMetadata: const ['标签', '天气'],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DeepSeek'), findsOneWidget);
    expect(find.textContaining('deepseek-chat'), findsOneWidget);
    expect(find.textContaining('1 条'), findsOneWidget);
    expect(find.textContaining('256'), findsOneWidget);
    expect(find.text('原文'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);
    expect(find.text('天气'), findsOneWidget);
    expect(find.text('仅本次允许'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('确认返回 true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showCloudAiConsentDialog(
                context: context,
                model: 'deepseek-chat',
                recordCount: 1,
                characterCount: 100,
                contentModeLabel: '原文',
                includedMetadata: const [],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('仅本次允许'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
