import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/services/ai/ai_api_client.dart';
import 'package:isle_log/services/ai/ai_models.dart';

void main() {
  group('AiApiClient.suggestTags', () {
    test('DeepSeek 标签请求显式携带单次授权', () async {
      late RequestOptions captured;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              captured = options;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'suggestions': [
                      {
                        'name': '工作',
                        'isNew': false,
                        'confidence': 0.9,
                        'reason': '开发记录',
                      },
                    ],
                    'usage': {'promptTokens': 120, 'completionTokens': 30},
                  },
                ),
              );
            },
          ),
        );
      final client = AiApiClient.fromDio(dio);
      final result = await client.suggestTags(
        content: '修复同步问题',
        existingTags: const [AiExistingTag(name: '工作', count: 12)],
        provider: AiProvider.deepSeek,
        cloudConsent: true,
      );

      expect(captured.path, '/api/v1/ai/tag-suggestions');
      expect((captured.data as Map)['provider'], 'DEEPSEEK');
      expect((captured.data as Map)['cloudConsent'], isTrue);
      expect((captured.data as Map)['existingTags'], [
        {'name': '工作', 'count': 12},
      ]);
      expect(result, hasLength(1));
      expect(result.single.name, '工作');
      expect(result.single.isNew, isFalse);
      expect(result.single.confidence, 0.9);
    });

    test('LOCAL 标签请求不携带授权字段以外的云端标记', () async {
      late RequestOptions captured;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              captured = options;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'suggestions': [],
                    'usage': {'promptTokens': 1, 'completionTokens': 1},
                  },
                ),
              );
            },
          ),
        );
      final client = AiApiClient.fromDio(dio);
      await client.suggestTags(
        content: '内容',
        existingTags: const [],
        provider: AiProvider.local,
        cloudConsent: false,
      );

      expect((captured.data as Map)['provider'], 'LOCAL');
    });

    test('服务端中文 message 映射为 AiApiException', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 403,
                    data: {'code': 403, 'message': '使用云端模型需要本次授权'},
                  ),
                ),
              );
            },
          ),
        );
      final client = AiApiClient.fromDio(dio);
      await expectLater(
        client.suggestTags(
          content: '内容',
          existingTags: const [],
          provider: AiProvider.deepSeek,
          cloudConsent: false,
        ),
        throwsA(
          isA<AiApiException>()
              .having((e) => e.message, 'message', '使用云端模型需要本次授权')
              .having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('取消请求转换为 AiRequestCancelled', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.cancel,
                ),
              );
            },
          ),
        );
      final client = AiApiClient.fromDio(dio);
      await expectLater(
        client.suggestTags(
          content: '内容',
          existingTags: const [],
          provider: AiProvider.local,
          cloudConsent: false,
          cancelToken: CancelToken(),
        ),
        throwsA(isA<AiRequestCancelled>()),
      );
    });
  });

  group('AiApiClient.polish', () {
    for (final entry in {
      'light': 'LIGHT',
      'medium': 'MEDIUM',
      'deep': 'DEEP',
      'formatOnly': 'FORMAT_ONLY',
    }.entries) {
      test('${entry.key} 模式映射为服务端 ${entry.value}', () async {
        late RequestOptions captured;
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                captured = options;
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'segments': [
                        {
                          'sourceIndexes': [0],
                          'originalText': '第一段。',
                          'revisedText': '第一段已润色。',
                          'reason': '语句通顺',
                        },
                      ],
                      'usage': {'promptTokens': 10, 'completionTokens': 5},
                    },
                  ),
                );
              },
            ),
          );
        final client = AiApiClient.fromDio(dio);
        final result = await client.polish(
          content: '第一段。',
          mode: PolishMode.values.byName(entry.key),
          provider: AiProvider.local,
          cloudConsent: false,
        );

        expect(captured.path, '/api/v1/ai/polish');
        expect((captured.data as Map)['mode'], entry.value);
        expect(result, hasLength(1));
        expect(result.single.sourceIndexes, [0]);
        expect(result.single.originalText, '第一段。');
        expect(result.single.revisedText, '第一段已润色。');
      });
    }
  });

  group('AiApiClient.listProviders', () {
    test('解析固定顺序的 Provider 状态', () async {
      late RequestOptions captured;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              captured = options;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    {
                      'name': 'LOCAL',
                      'enabled': true,
                      'available': true,
                      'model': 'qwen-local',
                      'contextLength': 32768,
                      'checkedAt': '2026-07-31T10:00:00Z',
                    },
                    {
                      'name': 'DEEPSEEK',
                      'enabled': false,
                      'available': false,
                      'model': '',
                      'contextLength': 0,
                      'checkedAt': '2026-07-31T10:00:00Z',
                      'message': '未配置',
                    },
                  ],
                ),
              );
            },
          ),
        );
      final client = AiApiClient.fromDio(dio);
      final result = await client.listProviders();

      expect(captured.path, '/api/v1/ai/providers');
      expect(result, hasLength(2));
      expect(result[0].name, AiProvider.local);
      expect(result[0].enabled, isTrue);
      expect(result[0].available, isTrue);
      expect(result[0].model, 'qwen-local');
      expect(result[0].contextLength, 32768);
      expect(result[1].name, AiProvider.deepSeek);
      expect(result[1].enabled, isFalse);
      expect(result[1].message, '未配置');
    });

    test('缺失或错误类型字段抛出格式错误异常', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    {'name': 123, 'enabled': true},
                  ],
                ),
              );
            },
          ),
        );
      final client = AiApiClient.fromDio(dio);
      await expectLater(
        client.listProviders(),
        throwsA(
          isA<AiApiException>().having(
            (e) => e.message,
            'message',
            contains('数据格式无效'),
          ),
        ),
      );
    });
  });
}
