import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/settings/ai_settings_page.dart';
import 'package:isle_log/services/ai/ai_api_client.dart';
import 'package:isle_log/services/ai/ai_models.dart';

class _FakeGateway implements AiGateway {
  int listProvidersCalls = 0;

  @override
  Future<List<AiProviderStatus>> listProviders() async {
    listProvidersCalls++;
    return const [
      AiProviderStatus(
        name: AiProvider.local,
        enabled: true,
        available: true,
        model: 'qwen-local',
        contextLength: 32768,
      ),
      AiProviderStatus(
        name: AiProvider.deepSeek,
        enabled: false,
        available: false,
        model: '',
        contextLength: 0,
        message: '服务端未启用',
      ),
    ];
  }

  @override
  Future<List<AiTagSuggestion>> suggestTags({
    required String content,
    required List<AiExistingTag> existingTags,
    required AiProvider provider,
    required bool cloudConsent,
    CancelToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<AiPolishSegment>> polish({
    required String content,
    required PolishMode mode,
    required AiProvider provider,
    required bool cloudConsent,
    CancelToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('展示 Provider 名称、模型、可用状态和未启用提示', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(home: AiSettingsPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    expect(find.text('私有 Qwen'), findsOneWidget);
    expect(find.text('DeepSeek'), findsOneWidget);
    expect(find.textContaining('qwen-local'), findsOneWidget);
    expect(find.textContaining('可用'), findsWidgets);
    expect(find.text('服务端未启用'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('点击重新检测会再次请求', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(home: AiSettingsPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    expect(gateway.listProvidersCalls, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(gateway.listProvidersCalls, 2);
  });

  testWidgets('已启用但暂时离线时显示离线状态', (tester) async {
    final gateway = _OfflineLocalGateway();
    await tester.pumpWidget(
      MaterialApp(home: AiSettingsPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂时离线'), findsOneWidget);
  });
}

class _OfflineLocalGateway extends _FakeGateway {
  @override
  Future<List<AiProviderStatus>> listProviders() async {
    listProvidersCalls++;
    return const [
      AiProviderStatus(
        name: AiProvider.local,
        enabled: true,
        available: false,
        model: 'qwen-local',
        contextLength: 32768,
        message: '模型服务暂时不可用',
      ),
    ];
  }
}
