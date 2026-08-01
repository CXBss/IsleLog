import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:isle_log/services/ai/ai_api_client.dart';
import 'package:isle_log/services/ai/ai_models.dart';
import 'package:isle_log/services/ai/ai_service.dart';
import 'package:isle_log/services/settings/settings_service.dart';

enum _ProbeMode { success, notFound, networkError }

class _FakeGateway implements AiGateway {
  _FakeGateway(this.mode);

  final _ProbeMode mode;
  int listProvidersCalls = 0;

  @override
  Future<List<AiProviderStatus>> listProviders() async {
    listProvidersCalls++;
    switch (mode) {
      case _ProbeMode.success:
        return const [
          AiProviderStatus(
            name: AiProvider.local,
            enabled: true,
            available: true,
            model: 'qwen-local',
            contextLength: 32768,
          ),
        ];
      case _ProbeMode.notFound:
        throw const AiApiException('接口不存在 (404)', statusCode: 404);
      case _ProbeMode.networkError:
        throw const AiApiException('无法连接到模型服务');
    }
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AiService.isCapabilityAvailable', () {
    test('成功时缓存当前 server URL 支持 AI', () async {
      await SettingsService.setServerUrl('https://islelog.local');
      await SettingsService.setAccessToken('token');
      final service = AiService(gateway: _FakeGateway(_ProbeMode.success));

      expect(await service.isCapabilityAvailable(), isTrue);
      expect(
        await SettingsService.aiCapabilityFor('https://islelog.local'),
        isTrue,
      );
    });

    test('404 时缓存不支持', () async {
      await SettingsService.setServerUrl('https://islelog.local');
      await SettingsService.setAccessToken('token');
      final service = AiService(gateway: _FakeGateway(_ProbeMode.notFound));

      expect(await service.isCapabilityAvailable(), isFalse);
      expect(
        await SettingsService.aiCapabilityFor('https://islelog.local'),
        isFalse,
      );
    });

    test('断网时使用同 URL 的成功缓存', () async {
      await SettingsService.setServerUrl('https://islelog.local');
      await SettingsService.setAccessToken('token');
      expect(
        await AiService(
          gateway: _FakeGateway(_ProbeMode.success),
        ).isCapabilityAvailable(),
        isTrue,
      );

      final offline = AiService(gateway: _FakeGateway(_ProbeMode.networkError));
      expect(await offline.isCapabilityAvailable(), isTrue);
    });

    test('未配置服务器时返回 false 且不请求', () async {
      final gateway = _FakeGateway(_ProbeMode.success);
      expect(
        await AiService(gateway: gateway).isCapabilityAvailable(),
        isFalse,
      );
      expect(gateway.listProvidersCalls, 0);
    });
  });

  group('SettingsService AI 能力缓存', () {
    test('服务器地址变化时清除旧 AI 缓存', () async {
      await SettingsService.setServerUrl('https://old.example');
      await SettingsService.setAiCapability('https://old.example', true);

      await SettingsService.setServerUrl('https://new.example');

      expect(
        await SettingsService.aiCapabilityFor('https://old.example'),
        isNull,
      );
    });

    test('其他 URL 的缓存不得复用', () async {
      await SettingsService.setServerUrl('https://a.example');
      await SettingsService.setAiCapability('https://b.example', true);

      final offline = AiService(gateway: _FakeGateway(_ProbeMode.networkError));
      expect(await offline.isCapabilityAvailable(), isFalse);
    });
  });
}
