import 'package:dio/dio.dart';

/// Memos API 请求异常
class MemosApiException implements Exception {
  final String message;
  final int? statusCode;

  const MemosApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Memos v0.25 REST API 客户端
///
/// 使用 Bearer Token 认证，封装 Dio 请求并统一处理错误。
class MemosApiService {
  final Dio _dio;

  MemosApiService({required String baseUrl, required String token})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );

  // ── Memo CRUD ─────────────────────────────────────────────────

  /// 分页列出 memos
  Future<({List<Map<String, dynamic>> memos, String? nextPageToken})>
      listMemos({
    int pageSize = 100,
    String? pageToken,
    String? filter,
  }) async {
    try {
      final params = <String, dynamic>{'pageSize': pageSize};
      if (pageToken != null) params['pageToken'] = pageToken;
      if (filter != null) params['filter'] = filter;

      final res =
          await _dio.get('/api/v1/memos', queryParameters: params);
      final memos =
          List<Map<String, dynamic>>.from(res.data['memos'] ?? []);
      final next = res.data['nextPageToken'] as String?;
      return (
        memos: memos,
        nextPageToken: (next == null || next.isEmpty) ? null : next,
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 自动翻页，获取全部 memos
  Future<List<Map<String, dynamic>>> listAllMemos({
    String? filter,
  }) async {
    final all = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final result =
          await listMemos(pageToken: pageToken, filter: filter);
      all.addAll(result.memos);
      pageToken = result.nextPageToken;
    } while (pageToken != null);
    return all;
  }

  /// 创建 memo
  Future<Map<String, dynamic>> createMemo({
    required String content,
    String visibility = 'PRIVATE',
  }) async {
    try {
      final res = await _dio.post('/api/v1/memos', data: {
        'content': content,
        'visibility': visibility,
      });
      return Map<String, dynamic>.from(res.data);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 更新 memo（PATCH）
  ///
  /// [name] 为资源名，如 `"memos/1"`
  Future<Map<String, dynamic>> updateMemo({
    required String name,
    required String content,
    String visibility = 'PRIVATE',
  }) async {
    try {
      final res = await _dio.patch(
        '/api/v1/$name',
        data: {'content': content, 'visibility': visibility},
        queryParameters: {'updateMask': 'content,visibility'},
      );
      return Map<String, dynamic>.from(res.data);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 删除 memo
  Future<void> deleteMemo(String name) async {
    try {
      await _dio.delete('/api/v1/$name');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ── Connection Test ───────────────────────────────────────────

  /// 测试连接：获取当前用户信息
  ///
  /// 返回用户对象（已解包 `{ "user": {...} }` 外层）
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final res = await _dio.get('/api/v1/auth/me');
      // v0.25 返回 { "user": { ... } }，取内层
      final data = res.data;
      if (data is Map && data['user'] is Map) {
        return Map<String, dynamic>.from(data['user'] as Map);
      }
      return Map<String, dynamic>.from(data as Map);
    } on DioException catch (e) {
      // 某些部署没有此接口，回退到拉取首条 memo
      if (e.response?.statusCode == 404 ||
          e.response?.statusCode == 405) {
        try {
          await listMemos(pageSize: 1);
          return {'name': 'users/me'};
        } on DioException catch (e2) {
          throw _wrap(e2);
        }
      }
      throw _wrap(e);
    }
  }

  // ── Error Wrapping ────────────────────────────────────────────

  MemosApiException _wrap(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401) {
      return const MemosApiException('Token 无效或已过期，请重新生成',
          statusCode: 401);
    }
    if (code == 403) {
      return const MemosApiException('无权限访问，请检查 Token', statusCode: 403);
    }
    if (code == 404) {
      return MemosApiException('接口不存在 (404)，请确认服务器版本为 v0.22+',
          statusCode: 404);
    }
    if (e.response != null) {
      return MemosApiException(
          '服务器错误 $code: ${e.response?.statusMessage}',
          statusCode: code);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const MemosApiException('连接超时，请检查网络和服务器地址');
    }
    if (e.type == DioExceptionType.connectionError) {
      return const MemosApiException('无法连接到服务器，请检查地址是否正确');
    }
    return MemosApiException('网络错误：${e.message}');
  }
}
