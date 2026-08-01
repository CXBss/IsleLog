import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:isle_log/data/database/database_service.dart';
import 'package:isle_log/features/memo_editor/memo_editor_page.dart';
import 'package:isle_log/services/ai/ai_api_client.dart';
import 'package:isle_log/services/ai/ai_models.dart';
import 'package:isle_log/services/settings/settings_service.dart';

class FakeAiGateway implements AiGateway {
  List<AiProviderStatus> statuses = const [
    AiProviderStatus(
      name: AiProvider.local,
      enabled: true,
      available: true,
      model: 'qwen-local',
      contextLength: 32768,
    ),
    AiProviderStatus(
      name: AiProvider.deepSeek,
      enabled: true,
      available: true,
      model: 'deepseek-chat',
      contextLength: 65536,
    ),
  ];
  List<AiTagSuggestion> tagSuggestions = const [];
  List<AiPolishSegment> polishSegments = const [];
  Completer<void>? tagGate;
  Completer<void>? polishGate;
  bool failSuggest = false;
  bool failListProviders = false;
  int suggestCalls = 0;
  int polishCalls = 0;
  CancelToken? lastTagToken;
  CancelToken? lastPolishToken;

  @override
  Future<List<AiProviderStatus>> listProviders() async {
    if (failListProviders) {
      throw const AiApiException('无法连接到模型服务');
    }
    return statuses;
  }

  @override
  Future<List<AiTagSuggestion>> suggestTags({
    required String content,
    required List<AiExistingTag> existingTags,
    required AiProvider provider,
    required bool cloudConsent,
    CancelToken? cancelToken,
  }) async {
    suggestCalls++;
    lastTagToken = cancelToken;
    if (failSuggest) {
      throw const AiApiException('模型返回内容格式无效', statusCode: 502);
    }
    final gate = tagGate;
    if (gate != null) await gate.future;
    return tagSuggestions;
  }

  @override
  Future<List<AiPolishSegment>> polish({
    required String content,
    required PolishMode mode,
    required AiProvider provider,
    required bool cloudConsent,
    CancelToken? cancelToken,
  }) async {
    polishCalls++;
    lastPolishToken = cancelToken;
    final gate = polishGate;
    if (gate != null) await gate.future;
    return polishSegments;
  }
}

void main() {
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temporaryDirectory;
  late FakeAiGateway gateway;

  setUpAll(() async {
    final packageConfigFile = File('.dart_tool/package_config.json').absolute;
    final packageConfig =
        jsonDecode(await packageConfigFile.readAsString())
            as Map<String, dynamic>;
    final packages = packageConfig['packages'] as List<dynamic>;
    final isarFlutterLibs = packages.cast<Map<String, dynamic>>().firstWhere(
      (package) => package['name'] == 'isar_flutter_libs',
    );
    final configuredRootUri = packageConfigFile.uri.resolve(
      isarFlutterLibs['rootUri'] as String,
    );
    final rootUri = configuredRootUri.path.endsWith('/')
        ? configuredRootUri
        : configuredRootUri.replace(path: '${configuredRootUri.path}/');
    final libraryPath = Platform.isMacOS
        ? rootUri.resolve('macos/libisar.dylib').toFilePath()
        : Platform.isLinux
        ? rootUri.resolve('linux/libisar.so').toFilePath()
        : throw UnsupportedError('当前平台不支持 Isar 启动测试');
    await Isar.initializeIsarCore(libraries: {Abi.current(): libraryPath});
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'isle_log_editor_ai_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return temporaryDirectory.path;
          }
          return null;
        });
    gateway = FakeAiGateway();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return temporaryDirectory.path;
          }
          return null;
        });
    try {
      await (await DatabaseService.db).close(deleteFromDisk: true);
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
    }
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    bool? capabilityOverride = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MemoEditorPage(
          aiGateway: gateway,
          aiCapabilityOverride: capabilityOverride,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAiActionSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('memo-editor-ai-action')));
    await tester.pumpAndSettle();
  }

  testWidgets('能力覆盖为 false 时隐藏右上角 AI 入口', (tester) async {
    await pumpEditor(tester, capabilityOverride: false);
    expect(find.byKey(const Key('memo-editor-ai-action')), findsNothing);
  });

  testWidgets('探测失败但缓存成功时仍显示入口', (tester) async {
    gateway.failListProviders = true;
    await SettingsService.setServerUrl('https://islelog.local');
    await SettingsService.setAiCapability('https://islelog.local', true);
    await pumpEditor(tester, capabilityOverride: null);
    expect(find.byKey(const Key('memo-editor-ai-action')), findsOneWidget);
  });

  testWidgets('能力为 true 时显示右上角 AI 入口并弹出操作面板', (tester) async {
    await pumpEditor(tester);
    expect(find.byKey(const Key('memo-editor-ai-action')), findsOneWidget);

    await openAiActionSheet(tester);
    expect(find.text('AI 助手'), findsOneWidget);
    expect(find.text('标签建议'), findsOneWidget);
    expect(find.text('轻度润色'), findsOneWidget);
    expect(find.text('整理格式'), findsOneWidget);
  });

  testWidgets('标签只更新草稿不触发保存', (tester) async {
    gateway.tagSuggestions = const [
      AiTagSuggestion(name: '生活', isNew: true, confidence: 0.8, reason: '个人记录'),
    ];
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, '今天修复同步');

    await openAiActionSheet(tester);
    await tester.tap(find.text('标签建议'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#生活'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.text('今天修复同步\n\n#生活'), findsOneWidget);
    expect(find.byType(MemoEditorPage), findsOneWidget);
  });

  testWidgets('DeepSeek 每次请求都弹出确认', (tester) async {
    gateway.tagSuggestions = const [
      AiTagSuggestion(name: '工作', isNew: false, confidence: 0.9, reason: '开发'),
    ];
    await pumpEditor(tester, capabilityOverride: null);
    await tester.enterText(find.byType(TextField).first, '修复同步');

    await openAiActionSheet(tester);
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标签建议'));
    await tester.pumpAndSettle();

    expect(find.text('使用云端模型'), findsOneWidget);
    expect(gateway.suggestCalls, 0);

    await tester.tap(find.text('仅本次允许'));
    await tester.pumpAndSettle();
    expect(gateway.suggestCalls, 1);
  });

  testWidgets('AI 异常时原文不变并提示错误', (tester) async {
    gateway.failSuggest = true;
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, '原始内容');

    await openAiActionSheet(tester);
    await tester.tap(find.text('标签建议'));
    await tester.pumpAndSettle();

    expect(find.text('原始内容'), findsOneWidget);
    expect(find.text('模型返回内容格式无效'), findsOneWidget);
  });

  testWidgets('请求期间继续输入，旧结果不能覆盖新内容', (tester) async {
    gateway.tagGate = Completer<void>();
    gateway.tagSuggestions = const [
      AiTagSuggestion(name: '生活', isNew: true, confidence: 0.8, reason: 'x'),
    ];
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, '旧内容');

    await openAiActionSheet(tester);
    await tester.tap(find.text('标签建议'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '新内容');
    gateway.tagGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('新内容'), findsOneWidget);
    expect(find.textContaining('已变化'), findsOneWidget);
  });

  testWidgets('点击取消触发 CancelToken.cancel 且原文不变', (tester) async {
    gateway.tagGate = Completer<void>();
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, '原始内容');

    await openAiActionSheet(tester);
    await tester.tap(find.text('标签建议'));
    await tester.pump();

    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(gateway.lastTagToken!.isCancelled, isTrue);
    expect(find.text('原始内容'), findsOneWidget);
  });

  testWidgets('润色全文并在预览中应用', (tester) async {
    gateway.polishSegments = const [
      AiPolishSegment(
        sourceIndexes: [0],
        originalText: '第一段。',
        revisedText: '第一段已润色。',
        reason: '语句通顺',
      ),
    ];
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, '第一段。');

    await openAiActionSheet(tester);
    await tester.tap(find.text('轻度润色'));
    await tester.pumpAndSettle();

    expect(gateway.polishCalls, 1);
    await tester.tap(find.text('全部接受'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用所选'));
    await tester.pumpAndSettle();

    expect(find.text('第一段已润色。'), findsOneWidget);
  });
}
