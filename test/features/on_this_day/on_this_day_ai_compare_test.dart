import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/on_this_day/widgets/on_this_day_ai_compare.dart';
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
  ];
  OnThisDayCompareResult? nextResult;
  Object? nextError;
  AiProvider? lastProvider;

  @override
  Future<List<AiProviderStatus>> listProviders() async => statuses;

  @override
  Future<OnThisDayCompareResult> onThisDayCompare({
    required String memoName,
    AiProvider? provider,
    bool cloudConsent = false,
    CancelToken? cancelToken,
  }) async {
    lastProvider = provider;
    final error = nextError;
    if (error != null) throw error;
    return nextResult ??
        const OnThisDayCompareResult(
          pastSummary: '当时很平静。',
          now: OnThisDayNow(available: false, summary: '', sources: []),
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
  Future<MemorySearchResult> memorySearch({
    required String query,
    AiProvider? provider,
    bool cloudConsent = false,
    int? topK,
    CancelToken? cancelToken,
  }) async => throw UnimplementedError();
}

void main() {
  testWidgets('点击"查看 AI 对照"用全局模型展示当时/现在的对照', (tester) async {
    final gateway = _FakeGateway()
      ..nextResult = const OnThisDayCompareResult(
        pastSummary: '当时在纠结要不要换工作。',
        now: OnThisDayNow(
          available: true,
          summary: '最近在筹备发布会。',
          sources: ['memos/9001'],
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnThisDayAiCompare(memoName: 'memos/456', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看 AI 对照'));
    await tester.pumpAndSettle();

    // 不指定模型：服务端使用设置里选定的全局模型
    expect(gateway.lastProvider, isNull);
    expect(find.text('当时在纠结要不要换工作。'), findsOneWidget);
    expect(find.text('最近在筹备发布会。'), findsOneWidget);
    expect(find.text('收起 AI 对照'), findsOneWidget);
  });

  testWidgets('now.available=false 时展示"暂时无法对照"而不是空白', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnThisDayAiCompare(memoName: 'memos/456', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看 AI 对照'));
    await tester.pumpAndSettle();

    expect(find.text('最近没有记录，暂时无法对照'), findsOneWidget);
  });

  testWidgets('请求失败时展示错误信息', (tester) async {
    final gateway = _FakeGateway()..nextError = const AiApiException('生成失败');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnThisDayAiCompare(memoName: 'memos/456', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看 AI 对照'));
    await tester.pumpAndSettle();

    expect(find.text('生成失败'), findsOneWidget);
  });

  testWidgets('不再提供单独的云端入口和逐次授权', (tester) async {
    final gateway = _FakeGateway()
      ..statuses = const [
        AiProviderStatus(
          name: AiProvider.deepSeek,
          enabled: true,
          available: true,
          model: 'deepseek-chat',
          contextLength: 65536,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnThisDayAiCompare(memoName: 'memos/456', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_outlined), findsNothing);
    expect(find.text('使用云端模型'), findsNothing);
  });
}
