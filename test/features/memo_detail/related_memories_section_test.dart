import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/memo_detail/widgets/related_memories_section.dart';
import 'package:isle_log/services/ai/ai_api_client.dart';
import 'package:isle_log/services/ai/ai_models.dart';

class _FakeGateway implements AiGateway {
  RelatedMemoriesResult? nextResult;
  Object? nextError;

  @override
  Future<RelatedMemoriesResult> relatedMemories({
    required String memoName,
    int? limit,
    CancelToken? cancelToken,
  }) async {
    final error = nextError;
    if (error != null) throw error;
    return nextResult ??
        const RelatedMemoriesResult(relatedMemos: [], pending: false);
  }

  @override
  Future<List<AiProviderStatus>> listProviders() async => throw UnimplementedError();

  @override
  Future<List<AiTagSuggestion>> suggestTags({
    required String content,
    required List<AiExistingTag> existingTags,
    required AiProvider provider,
    required bool cloudConsent,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<List<AiPolishSegment>> polish({
    required String content,
    required PolishMode mode,
    required AiProvider provider,
    required bool cloudConsent,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<MemorySearchResult> memorySearch({
    required String query,
    required AiProvider provider,
    required bool cloudConsent,
    int? topK,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<OnThisDayCompareResult> onThisDayCompare({
    required String memoName,
    required AiProvider provider,
    required bool cloudConsent,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();
}

void main() {
  testWidgets('pending 时展示"正在分析"占位', (tester) async {
    final gateway = _FakeGateway()
      ..nextResult = const RelatedMemoriesResult(relatedMemos: [], pending: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelatedMemoriesSection(memoName: 'memos/1', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('正在分析关联记忆…'), findsOneWidget);
  });

  testWidgets('结果为空且非 pending 时整块不渲染', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelatedMemoriesSection(memoName: 'memos/1', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('相关记忆'), findsNothing);
  });

  testWidgets('有结果时展示日期、片段和匹配原因', (tester) async {
    final gateway = _FakeGateway()
      ..nextResult = RelatedMemoriesResult(
        relatedMemos: [
          RelatedMemory(
            memo: 'memos/998',
            displayTime: DateTime(2025, 8, 2),
            snippet: '今天又去了海边',
            similarity: 0.71,
            matchReason: '地点相近 · 标签重合',
          ),
        ],
        pending: false,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelatedMemoriesSection(memoName: 'memos/1', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('相关记忆'), findsOneWidget);
    expect(find.textContaining('今天又去了海边'), findsOneWidget);
    expect(find.text('地点相近 · 标签重合'), findsOneWidget);
  });

  testWidgets('加载失败时整块不渲染', (tester) async {
    final gateway = _FakeGateway()..nextError = const AiApiException('查询失败');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RelatedMemoriesSection(memoName: 'memos/1', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('相关记忆'), findsNothing);
    expect(find.textContaining('查询失败'), findsNothing);
  });
}
