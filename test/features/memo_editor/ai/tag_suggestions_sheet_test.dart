import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/memo_editor/ai/tag_suggestions_sheet.dart';
import 'package:isle_log/services/ai/ai_models.dart';

void main() {
  testWidgets('区分已有标签和新建候选，未勾选时不能应用', (tester) async {
    List<String>? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              applied = await showTagSuggestionsSheet(
                context: context,
                existingTags: const ['工作'],
                suggestions: const [
                  AiTagSuggestion(
                    name: '工作',
                    isNew: false,
                    confidence: 0.9,
                    reason: '开发记录',
                  ),
                  AiTagSuggestion(
                    name: '生活',
                    isNew: true,
                    confidence: 0.7,
                    reason: '个人记录',
                  ),
                ],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('#工作'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.textContaining('90%'), findsOneWidget);
    expect(find.textContaining('70%'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(applied, isEmpty);
  });

  testWidgets('勾选后返回所选标签', (tester) async {
    List<String>? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              applied = await showTagSuggestionsSheet(
                context: context,
                existingTags: const ['工作'],
                suggestions: const [
                  AiTagSuggestion(
                    name: '工作',
                    isNew: false,
                    confidence: 0.9,
                    reason: '开发记录',
                  ),
                  AiTagSuggestion(
                    name: '生活',
                    isNew: true,
                    confidence: 0.7,
                    reason: '个人记录',
                  ),
                ],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#生活'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(applied, ['生活']);
  });

  testWidgets('取消返回 null', (tester) async {
    List<String>? applied = ['初始'];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              applied = await showTagSuggestionsSheet(
                context: context,
                existingTags: const ['工作'],
                suggestions: const [
                  AiTagSuggestion(
                    name: '工作',
                    isNew: false,
                    confidence: 0.9,
                    reason: '开发记录',
                  ),
                ],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(applied, isNull);
  });
}
