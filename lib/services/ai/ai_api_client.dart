import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'ai_models.dart';
import 'ai_profile_models.dart';

/// AI 编辑辅助网关接口，供 UI 注入 Fake 或真实实现。
///
/// 模型由用户在设置里全局选定（服务端保存）。[AiProvider] 参数只为兼容旧调用
/// 保留：新代码一律不传，由服务端使用全局模型。
abstract interface class AiGateway {
  /// 获取模型提供者状态列表（固定 LOCAL、DEEPSEEK 两项）。
  Future<List<AiProviderStatus>> listProviders();

  /// 请求标签建议。[vault] 为 true 时服务端只用本地模型。
  Future<List<AiTagSuggestion>> suggestTags({
    required String content,
    required List<AiExistingTag> existingTags,
    AiProvider? provider,
    bool cloudConsent = false,
    bool vault = false,
    CancelToken? cancelToken,
  });

  /// 请求润色片段。[vault] 为 true 时服务端只用本地模型。
  Future<List<AiPolishSegment>> polish({
    required String content,
    required PolishMode mode,
    AiProvider? provider,
    bool cloudConsent = false,
    bool vault = false,
    CancelToken? cancelToken,
  });

  /// 自然语言记忆检索问答。
  ///
  /// 检索不到依据、或模型认为候选不足以回答时，返回
  /// `insufficientEvidence: true` 的正常结果，不是异常。
  Future<MemorySearchResult> memorySearch({
    required String query,
    AiProvider? provider,
    bool cloudConsent = false,
    int? topK,
    CancelToken? cancelToken,
  });

  /// 获取指定日记的"相关记忆"。纯向量相似度计算，不涉及 provider/cloudConsent。
  Future<RelatedMemoriesResult> relatedMemories({
    required String memoName,
    int? limit,
    CancelToken? cancelToken,
  });

  /// "往年今日"AI 对照。
  Future<OnThisDayCompareResult> onThisDayCompare({
    required String memoName,
    AiProvider? provider,
    bool cloudConsent = false,
    CancelToken? cancelToken,
  });
}

/// 模型配置管理网关（设置页使用）。
abstract interface class AiProfileGateway {
  /// AI 发送记录，按时间倒序分页。
  Future<AiTransmissionPage> listTransmissions({String? pageToken});

  /// 全部配置（含健康状态）、当前全局模型与敏感标签。
  Future<AiProfileSettings> listProfiles();

  /// 新建配置；服务端先测试连接，失败时抛出 [AiApiException]。
  Future<AiModelProfile> createProfile(AiProfileDraft draft);

  /// 修改配置；[AiProfileDraft.apiKey] 为 null 表示保持原 Key。
  Future<AiModelProfile> updateProfile(String name, AiProfileDraft draft);

  Future<void> deleteProfile(String name);

  /// 测试连接（不保存）。编辑已有配置时传 [existing]，服务端借用库里的 Key。
  Future<AiProfileTestResult> testProfile(
    AiProfileDraft draft, {
    String? existing,
  });

  /// 拉取服务商的模型列表（不保存）。
  Future<List<String>> listRemoteModels({
    required String baseUrl,
    String? apiKey,
    String? existing,
  });

  /// 修改全局模型和/或敏感标签，返回最新设置。
  Future<AiProfileSettings> updateSettings({
    String? activeProfile,
    List<String>? sensitiveTags,
  });
}

/// IsleLog 自建服务 AI 网关客户端。
///
/// 仅对接 IsleLog 服务端 `/api/v1/ai/*` 接口，不属于标准 Memos API。
/// 所有请求使用 Bearer Token 认证；日志不记录正文和完整响应。
class AiApiClient implements AiGateway, AiProfileGateway {
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
    AiProvider? provider,
    bool cloudConsent = false,
    bool vault = false,
    CancelToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[AI] suggestTags 字符数=${content.length} vault=$vault');
    try {
      final res = await _dio.post(
        '/api/v1/ai/tag-suggestions',
        data: {
          'content': content,
          'existingTags': existingTags.map((e) => e.toJson()).toList(),
          ..._providerFields(provider, cloudConsent),
          if (vault) 'vault': true,
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
    AiProvider? provider,
    bool cloudConsent = false,
    bool vault = false,
    CancelToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint(
      '[AI] polish mode=${mode.serverValue} 字符数=${content.length} vault=$vault',
    );
    try {
      final res = await _dio.post(
        '/api/v1/ai/polish',
        data: {
          'content': content,
          'mode': mode.serverValue,
          ..._providerFields(provider, cloudConsent),
          if (vault) 'vault': true,
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

  @override
  Future<MemorySearchResult> memorySearch({
    required String query,
    AiProvider? provider,
    bool cloudConsent = false,
    int? topK,
    CancelToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[AI] memorySearch');
    try {
      final res = await _dio.post(
        '/api/v1/ai/memory-search',
        data: {
          'query': query,
          ..._providerFields(provider, cloudConsent),
          if (topK != null) 'topK': topK,
        },
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw const AiApiException('AI 返回的数据格式无效');
      }
      final result = MemorySearchResult.fromJson(data);
      debugPrint(
        '[AI] memorySearch 完成，insufficientEvidence=${result.insufficientEvidence} '
        '来源数=${result.sources.length}，耗时 ${sw.elapsedMilliseconds}ms',
      );
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<RelatedMemoriesResult> relatedMemories({
    required String memoName,
    int? limit,
    CancelToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[AI] relatedMemories $memoName');
    try {
      final res = await _dio.get(
        '/api/v1/$memoName/related-memories',
        queryParameters: {if (limit != null) 'limit': limit},
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw const AiApiException('AI 返回的数据格式无效');
      }
      final result = RelatedMemoriesResult.fromJson(data);
      debugPrint(
        '[AI] relatedMemories 完成 ${result.relatedMemos.length} 条，'
        '耗时 ${sw.elapsedMilliseconds}ms',
      );
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<OnThisDayCompareResult> onThisDayCompare({
    required String memoName,
    AiProvider? provider,
    bool cloudConsent = false,
    CancelToken? cancelToken,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[AI] onThisDayCompare $memoName');
    try {
      final res = await _dio.post(
        '/api/v1/ai/on-this-day-compare',
        data: {'memo': memoName, ..._providerFields(provider, cloudConsent)},
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw const AiApiException('AI 返回的数据格式无效');
      }
      final result = OnThisDayCompareResult.fromJson(data);
      debugPrint(
        '[AI] onThisDayCompare 完成，nowAvailable=${result.now.available}，'
        '耗时 ${sw.elapsedMilliseconds}ms',
      );
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 不传 provider 时服务端使用用户的全局模型。
  Map<String, dynamic> _providerFields(
    AiProvider? provider,
    bool cloudConsent,
  ) => provider == null
      ? const {}
      : {'provider': provider.serverValue, 'cloudConsent': cloudConsent};

  // ── 发送记录 ──────────────────────────────────────────────────

  @override
  Future<AiTransmissionPage> listTransmissions({String? pageToken}) async {
    try {
      final res = await _dio.get(
        '/api/v1/ai/transmissions',
        queryParameters: {'pageSize': 50, 'pageToken': ?pageToken},
      );
      final data = res.data;
      final list = data is Map<String, dynamic> ? data['transmissions'] : null;
      if (list is! List) throw const AiApiException('发送记录格式无效');
      return AiTransmissionPage(
        items: list
            .whereType<Map<String, dynamic>>()
            .map(AiTransmission.fromJson)
            .toList(),
        nextPageToken: data['nextPageToken'] as String?,
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ── 模型配置 ──────────────────────────────────────────────────

  @override
  Future<AiProfileSettings> listProfiles() async {
    try {
      final res = await _dio.get('/api/v1/ai/profiles');
      return _parseSettings(res.data);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<AiModelProfile> createProfile(AiProfileDraft draft) async {
    try {
      final res = await _dio.post(
        '/api/v1/ai/profiles',
        data: draft.toJson(),
        // 服务端要先做一次真实的连接测试
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return _parseProfile(res.data);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<AiModelProfile> updateProfile(
    String name,
    AiProfileDraft draft,
  ) async {
    try {
      final res = await _dio.patch(
        '/api/v1/ai/profiles/${_idOf(name)}',
        data: draft.toJson(),
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      return _parseProfile(res.data);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> deleteProfile(String name) async {
    try {
      await _dio.delete('/api/v1/ai/profiles/${_idOf(name)}');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<AiProfileTestResult> testProfile(
    AiProfileDraft draft, {
    String? existing,
  }) async {
    try {
      final res = await _dio.post(
        '/api/v1/ai/profiles/test',
        data: {...draft.toJson(), if (existing != null) 'profile': existing},
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw const AiApiException('AI 返回的数据格式无效');
      }
      return AiProfileTestResult.fromJson(data);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<List<String>> listRemoteModels({
    required String baseUrl,
    String? apiKey,
    String? existing,
  }) async {
    try {
      final res = await _dio.post(
        '/api/v1/ai/profiles/models',
        data: {
          'baseUrl': baseUrl,
          if (apiKey != null) 'apiKey': apiKey,
          if (existing != null) 'profile': existing,
        },
      );
      final data = res.data;
      if (data is! Map<String, dynamic> || data['models'] is! List) {
        throw const AiApiException('AI 返回的数据格式无效');
      }
      return (data['models'] as List).whereType<String>().toList();
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<AiProfileSettings> updateSettings({
    String? activeProfile,
    List<String>? sensitiveTags,
  }) async {
    try {
      final res = await _dio.patch(
        '/api/v1/ai/settings',
        data: {
          if (activeProfile != null) 'activeProfile': activeProfile,
          if (sensitiveTags != null) 'sensitiveTags': sensitiveTags,
        },
      );
      return _parseSettings(res.data);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  static String _idOf(String name) => name.replaceFirst('aiProfiles/', '');

  AiProfileSettings _parseSettings(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return AiProfileSettings.fromJson(data);
  }

  AiModelProfile _parseProfile(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const AiApiException('AI 返回的数据格式无效');
    }
    return AiModelProfile.fromJson(data);
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
