import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'ai_models.dart';

/// AI 编辑辅助网关接口，供 UI 注入 Fake 或真实实现。
abstract interface class AiGateway {
  /// 获取模型提供者状态列表（固定 LOCAL、DEEPSEEK 两项）。
  Future<List<AiProviderStatus>> listProviders();

  /// 请求标签建议。
  Future<List<AiTagSuggestion>> suggestTags({
    required String content,
    required List<AiExistingTag> existingTags,
    required AiProvider provider,
    required bool cloudConsent,
    CancelToken? cancelToken,
  });

  /// 请求润色片段。
  Future<List<AiPolishSegment>> polish({
    required String content,
    required PolishMode mode,
    required AiProvider provider,
    required bool cloudConsent,
    CancelToken? cancelToken,
  });
}

/// IsleLog 自建服务 AI 网关客户端。
///
/// 仅对接 IsleLog 服务端 `/api/v1/ai/*` 接口，不属于标准 Memos API。
/// 所有请求使用 Bearer Token 认证；日志不记录正文和完整响应。
class AiApiClient implements AiGateway {
  final Dio _dio;

  /// 生产构造函数。
  ///
  /// [baseUrl]：服务器地址（不带末尾斜杠）
  /// [token]：Access Token
  AiApiClient({required String baseUrl, required String token})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

  /// 测试构造函数，注入已配置拦截器的 [Dio]。
  @visibleForTesting
  AiApiClient.fromDio(this._dio);

  @override
  Future<List<AiProviderStatus>> listProviders() async {
    final sw = Stopwatch()..start();
    debugPrint('[AI] listProviders');
    try {
      final res = await _dio.get('/api/v1/ai/providers');
      final data = res.data;
      if (data is! List) {
        throw const AiApiException('AI 返回的数据格式无效');
      }
      final result = data
          .map(
            (e) => e is Map<String, dynamic>
                ? AiProviderStatus.fromJson(e)
                : throw const AiApiException('AI 返回的数据格式无效'),
          )
          .toList();
      debugPrint('[AI] listProviders 完成，耗时 ${sw.elapsedMilliseconds}ms');
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
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
    final sw = Stopwatch()..start();
    debugPrint(
      '[AI] suggestTags 字符数=${content.length} provider=${provider.serverValue}',
    );
    try {
      final res = await _dio.post(
        '/api/v1/ai/tag-suggestions',
        data: {
          'content': content,
          'existingTags': existingTags.map((e) => e.toJson()).toList(),
          'provider': provider.serverValue,
          'cloudConsent': cloudConsent,
        },
        cancelToken: cancelToken,
      );
      final result = _parseSuggestionList(res.data);
      debugPrint(
        '[AI] suggestTags 完成 ${result.length} 条，耗时 ${sw.elapsedMilliseconds}ms',
      );
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<List<AiPolishSegment>> polish({
    required String content,
    required PolishMode mode,
    required AiProvider provider,
    required bool cloudConsent,
    CancelToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint(
      '[AI] polish mode=${mode.serverValue} 字符数=${content.length} provider=${provider.serverValue}',
    );
    try {
      final res = await _dio.post(
        '/api/v1/ai/polish',
        data: {
          'content': content,
          'mode': mode.serverValue,
          'provider': provider.serverValue,
          'cloudConsent': cloudConsent,
        },
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data is! Map<String, dynamic> || data['segments'] is! List) {
        throw const AiApiException('AI 返回的数据格式无效');
      }
      final result = (data['segments'] as List)
          .map(
            (e) => e is Map<String, dynamic>
                ? AiPolishSegment.fromJson(e)
                : throw const AiApiException('AI 返回的数据格式无效'),
          )
          .toList();
      debugPrint(
        '[AI] polish 完成 ${result.length} 段，耗时 ${sw.elapsedMilliseconds}ms',
      );
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  List<AiTagSuggestion> _parseSuggestionList(dynamic data) {
    if (data is! Map<String, dynamic> || data['suggestions'] is! List) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return (data['suggestions'] as List)
        .map(
          (e) => e is Map<String, dynamic>
              ? AiTagSuggestion.fromJson(e)
              : throw const AiApiException('AI 返回的数据格式无效'),
        )
        .toList();
  }

  /// 将 [DioException] 转换为 [AiApiException] 或 [AiRequestCancelled]。
  AiApiException _wrap(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      throw const AiRequestCancelled();
    }
    final code = e.response?.statusCode;
    final serverMessage = e.response?.data is Map<String, dynamic>
        ? (e.response!.data as Map<String, dynamic>)['message']
        : null;
    if (serverMessage is String && serverMessage.isNotEmpty) {
      return AiApiException(serverMessage, statusCode: code);
    }
    if (e.response != null) {
      return AiApiException('AI 请求失败（$code）', statusCode: code);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const AiApiException('AI 请求超时，请检查网络和服务器地址');
    }
    if (e.type == DioExceptionType.connectionError) {
      return const AiApiException('无法连接到模型服务');
    }
    return AiApiException('AI 请求失败：${e.message}');
  }
}
