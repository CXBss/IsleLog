import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/memory_search/memory_search_page.dart';
import 'package:isle_log/services/ai/ai_api_client.dart';
import 'package:isle_log/services/ai/ai_models.dart';

class _FakeGateway implements AiGateway {
  List<AiProviderStatus> statuses = const [
    AiProviderStatus(
      name: AiProvider.local,
      enabled: true,
      available: true,
      model: 'qwen-local',
      contextLength: 32768,
    ),
    AiProviderStatus(
      name: AiProvider.localEmbedding,
      enabled: true,
      available: true,
      model: 'bge-m3',
      contextLength: 0,
    ),
  ];
  MemorySearchResult? nextResult;
  Object? nextError;
  String? lastQuery;
  AiProvider? lastProvider;

  @override
  Future<List<AiProviderStatus>> listProviders() async => statuses;

  @override
  Future<MemorySearchResult> memorySearch({
    required String query,
    AiProvider? provider,
    bool cloudConsent = false,
    int? topK,
    CancelToken? cancelToken,
  }) async {
    lastQuery = query;
    lastProvider = provider;
    final error = nextError;
    if (error != null) throw error;
    return nextResult ??
        const MemorySearchResult(
          answer: '',
          insufficientEvidence: true,
          sources: [],
          indexIncomplete: false,
        );
  }

  @override
  Future<List<AiTagSuggestion>> suggestTags({
    required String content,
    required List<AiExistingTag> existingTags,
    AiProvider? provider,
    bool cloudConsent = false,
    bool vault = false,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<List<AiPolishSegment>> polish({
    required String content,
    required PolishMode mode,
    AiProvider? provider,
    bool cloudConsent = false,
    bool vault = false,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<RelatedMemoriesResult> relatedMemories({
    required String memoName,
    int? limit,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();

  @override
  Future<OnThisDayCompareResult> onThisDayCompare({
    required String memoName,
    AiProvider? provider,
    bool cloudConsent = false,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();
}

void main() {
  testWidgets('embedding 未启用时展示未启用空态且不显示输入框', (tester) async {
    final gateway = _FakeGateway()
      ..statuses = const [
        AiProviderStatus(
          name: AiProvider.local,
          enabled: true,
          available: true,
          model: 'qwen-local',
          contextLength: 32768,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(home: MemorySearchPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    expect(find.text('记忆检索尚未启用'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('提问后展示答案和来源卡片', (tester) async {
    final gateway = _FakeGateway()
      ..nextResult = MemorySearchResult(
        answer: '去年夏天你提到去过厦门。',
        insufficientEvidence: false,
        sources: [
          MemorySource(
            memo: 'memos/1001',
            displayTime: DateTime(2025, 7, 12),
            snippet: '去了厦门',
            similarity: 0.81,
          ),
        ],
        indexIncomplete: false,
      );
    await tester.pumpWidget(
      MaterialApp(home: MemorySearchPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '去年夏天去过哪里？');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(gateway.lastQuery, '去年夏天去过哪里？');
    // 不指定模型：服务端使用设置里选定的全局模型
    expect(gateway.lastProvider, isNull);
    expect(find.text('去年夏天去过哪里？'), findsOneWidget);
    expect(find.text('去年夏天你提到去过厦门。'), findsOneWidget);
    expect(find.textContaining('去了厦门'), findsOneWidget);
  });

  testWidgets('无依据结果展示空态文案而不是报错样式', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(home: MemorySearchPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '一个查不到的问题');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('没有找到相关日记，换个问法试试？'), findsOneWidget);
  });

  testWidgets('请求失败时展示服务端错误信息', (tester) async {
    final gateway = _FakeGateway()..nextError = const AiApiException('模型服务暂时不可用');
    await tester.pumpWidget(
      MaterialApp(home: MemorySearchPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '问题');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('模型服务暂时不可用'), findsOneWidget);
  });
}
