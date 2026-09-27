import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/settings/ai_transmissions_page.dart';
import 'package:isle_log/services/ai/ai_api_client.dart';
import 'package:isle_log/services/ai/ai_models.dart';

class _FakeGateway implements AiProfileGateway {
  final tokens = <String?>[];

  @override
  Future<AiTransmissionPage> listTransmissions({String? pageToken}) async {
    tokens.add(pageToken);
    return AiTransmissionPage(
      items: [
        AiTransmission.fromJson({
          'name': 'aiTransmissions/2',
          'time': '2026-09-27T08:00:00Z',
          'feature': 'ASSISTANT',
          'model': 'DeepSeek',
          'cloud': true,
          'memos': ['memos/1', 'memos/2'],
        }),
        AiTransmission.fromJson({
          'name': 'aiTransmissions/1',
          'time': '2026-09-26T08:00:00Z',
          'feature': 'POLISH',
          'model': '私有 Qwen',
          'cloud': false,
          'chars': 320,
        }),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('列出每次发送：功能、篇数或字数、模型与是否云端', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(home: AiTransmissionsPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    expect(find.text('AI 助手 · 2 篇日记'), findsOneWidget);
    expect(find.textContaining('DeepSeek（云端）'), findsOneWidget);
    expect(find.text('润色 · 编辑器正文 320 字'), findsOneWidget);
    expect(find.textContaining('私有 Qwen（本地）'), findsOneWidget);
    expect(find.text('没有更早的记录了'), findsOneWidget);
    expect(gateway.tokens, [null]);
  });
}
