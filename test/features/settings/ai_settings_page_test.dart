import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/settings/ai_profile_edit_page.dart';
import 'package:isle_log/features/settings/ai_settings_page.dart';
import 'package:isle_log/services/ai/ai_api_client.dart';
import 'package:isle_log/services/ai/ai_models.dart';
import 'package:isle_log/services/ai/ai_profile_models.dart';

AiModelProfile _profile(
  String id,
  AiProfileKind kind,
  String displayName, {
  bool available = true,
  bool keyUnreadable = false,
}) => AiModelProfile(
  name: 'aiProfiles/$id',
  kind: kind,
  displayName: displayName,
  baseUrl: kind == AiProfileKind.local
      ? 'http://nas:8080/v1'
      : 'https://api.deepseek.com/v1',
  hasApiKey: kind == AiProfileKind.cloud,
  apiKeyHint: kind == AiProfileKind.cloud ? '…a3f9' : '',
  keyUnreadable: keyUnreadable,
  model: kind == AiProfileKind.local ? 'qwen3.8' : 'deepseek-chat',
  contextLength: kind == AiProfileKind.local ? 131072 : 65536,
  timeoutSeconds: 120,
  maxConcurrency: 1,
  jsonMode: kind == AiProfileKind.cloud,
  status: AiProfileStatus(available: available),
);

class _FakeProfileGateway implements AiProfileGateway {
  @override
  Future<AiTransmissionPage> listTransmissions({String? pageToken}) async =>
      const AiTransmissionPage(items: []);

  AiProfileSettings settings = AiProfileSettings(
    profiles: [
      _profile('1', AiProfileKind.local, '私有 Qwen3.8'),
      _profile('2', AiProfileKind.cloud, 'DeepSeek V3'),
    ],
    activeProfile: 'aiProfiles/1',
    sensitiveTags: const ['私密'],
  );
  int listCalls = 0;
  String? lastActive;
  List<String>? lastTags;
  AiProfileDraft? created;
  String? deleted;

  @override
  Future<AiProfileSettings> listProfiles() async {
    listCalls++;
    return settings;
  }

  @override
  Future<AiProfileSettings> updateSettings({
    String? activeProfile,
    List<String>? sensitiveTags,
  }) async {
    lastActive = activeProfile ?? lastActive;
    lastTags = sensitiveTags ?? lastTags;
    settings = AiProfileSettings(
      profiles: settings.profiles,
      activeProfile: activeProfile ?? settings.activeProfile,
      sensitiveTags: sensitiveTags ?? settings.sensitiveTags,
    );
    return settings;
  }

  @override
  Future<AiModelProfile> createProfile(AiProfileDraft draft) async {
    created = draft;
    return _profile('3', draft.kind, draft.displayName);
  }

  @override
  Future<AiModelProfile> updateProfile(
    String name,
    AiProfileDraft draft,
  ) async => _profile('1', draft.kind, draft.displayName);

  @override
  Future<void> deleteProfile(String name) async => deleted = name;

  @override
  Future<AiProfileTestResult> testProfile(
    AiProfileDraft draft, {
    String? existing,
  }) async =>
      const AiProfileTestResult(ok: true, latencyMs: 120, jsonMode: true);

  @override
  Future<List<String>> listRemoteModels({
    required String baseUrl,
    String? apiKey,
    String? existing,
  }) async => const ['deepseek-chat', 'deepseek-reasoner'];
}

class _FakeGateway implements AiGateway {
  @override
  Future<List<AiProviderStatus>> listProviders() async => const [
    AiProviderStatus(
      name: AiProvider.localEmbedding,
      enabled: true,
      available: true,
      model: 'bge-m3',
      contextLength: 0,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, _FakeProfileGateway profiles) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AiSettingsPage(profileGateway: profiles, gateway: _FakeGateway()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('分组展示本地/云端模型、当前模型和敏感标签，不显示 Key 原文', (tester) async {
    final profiles = _FakeProfileGateway();
    await _pump(tester, profiles);

    expect(find.text('当前使用：私有 Qwen3.8（本地）'), findsOneWidget);
    expect(find.text('私有 Qwen3.8'), findsOneWidget);
    expect(find.text('DeepSeek V3'), findsOneWidget);
    expect(find.textContaining('Key …a3f9'), findsOneWidget);
    expect(find.text('#私密'), findsOneWidget);
    expect(find.textContaining('bge-m3'), findsOneWidget);
  });

  testWidgets('切换到云端模型前需要确认，取消则不切换', (tester) async {
    final profiles = _FakeProfileGateway();
    await _pump(tester, profiles);

    await tester.tap(find.text('DeepSeek V3'));
    await tester.pumpAndSettle();
    expect(find.text('使用 DeepSeek V3？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(profiles.lastActive, isNull);

    await tester.tap(find.text('DeepSeek V3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认使用'));
    await tester.pumpAndSettle();
    expect(profiles.lastActive, 'aiProfiles/2');
    expect(find.textContaining('当前使用：DeepSeek V3（云端'), findsOneWidget);
  });

  testWidgets('切换到本地模型不需要确认', (tester) async {
    final profiles = _FakeProfileGateway()
      ..settings = AiProfileSettings(
        profiles: [
          _profile('1', AiProfileKind.local, '私有 Qwen3.8'),
          _profile('2', AiProfileKind.cloud, 'DeepSeek V3'),
        ],
        activeProfile: 'aiProfiles/2',
        sensitiveTags: const [],
      );
    await _pump(tester, profiles);

    await tester.tap(find.text('私有 Qwen3.8'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(profiles.lastActive, 'aiProfiles/1');
  });

  testWidgets('Key 解不开时提示重新填写', (tester) async {
    final profiles = _FakeProfileGateway()
      ..settings = AiProfileSettings(
        profiles: [
          _profile(
            '2',
            AiProfileKind.cloud,
            'DeepSeek V3',
            keyUnreadable: true,
          ),
        ],
        activeProfile: 'aiProfiles/2',
        sensitiveTags: const [],
      );
    await _pump(tester, profiles);
    expect(find.text('Key 需重新填写'), findsOneWidget);
  });

  testWidgets('编辑敏感标签会去掉 # 并按空格拆分', (tester) async {
    final profiles = _FakeProfileGateway();
    await _pump(tester, profiles);

    await tester.tap(find.text('敏感标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '#私密  健康，#家庭');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(profiles.lastTags, ['私密', '健康', '家庭']);
  });

  testWidgets('点击重新检测会再次请求', (tester) async {
    final profiles = _FakeProfileGateway();
    await _pump(tester, profiles);
    expect(profiles.listCalls, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(profiles.listCalls, 2);
  });

  testWidgets('添加云端模型：选服务商自动填地址，获取列表后选模型，保存提交表单', (tester) async {
    final profiles = _FakeProfileGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: AiProfileEditPage(gateway: profiles, kind: AiProfileKind.cloud),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();
    expect(find.text('https://api.deepseek.com/v1'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'API Key'),
      'sk-new-key',
    );
    await tester.tap(find.text('获取列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('deepseek-chat'));
    await tester.pumpAndSettle();
    // 预设里有这个模型的上下文长度，自动填上
    expect(find.text('65536'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('保存'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final draft = profiles.created!;
    expect(draft.kind, AiProfileKind.cloud);
    expect(draft.displayName, 'DeepSeek');
    expect(draft.apiKey, 'sk-new-key');
    expect(draft.model, 'deepseek-chat');
    expect(draft.contextLength, 65536);
  });

  testWidgets('云端模型没填 Key 不能保存', (tester) async {
    final profiles = _FakeProfileGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: AiProfileEditPage(gateway: profiles, kind: AiProfileKind.cloud),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('保存'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('云端模型需要 API Key'), findsOneWidget);
    expect(profiles.created, isNull);
  });

  testWidgets('编辑已有云端模型时 Key 可以留空（沿用原 Key）', (tester) async {
    final profiles = _FakeProfileGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: AiProfileEditPage(
          gateway: profiles,
          kind: AiProfileKind.cloud,
          existing: _profile('2', AiProfileKind.cloud, 'DeepSeek V3'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('留空保持原 Key（…a3f9）'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('保存'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('云端模型需要 API Key'), findsNothing);
  });
}
