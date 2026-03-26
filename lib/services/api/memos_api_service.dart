import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

/// Memos API 请求异常
///
/// 封装网络请求失败时的错误信息，由 [MemosApiService._wrap] 统一转换。
class MemosApiException implements Exception {
  /// 用户可读的错误信息
  final String message;

  /// HTTP 状态码（网络层错误时为 null）
  final int? statusCode;

  const MemosApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Memos v0.22+ REST API 客户端
///
/// 基于 [Dio] 封装，使用 Bearer Token 认证。
/// 统一处理分页、错误转换等公共逻辑。
///
/// 支持的 API：
/// - [listMemos] / [listAllMemos]：分页/全量拉取 memo 列表
/// - [createMemo]：新建 memo
/// - [updateMemo]：更新 memo（PATCH，只更新指定字段）
/// - [deleteMemo]：删除 memo
/// - [testConnection]：测试连接并返回当前用户信息
class MemosApiService {
  final Dio _dio;

  /// 创建 API 客户端
  ///
  /// [baseUrl]：服务器地址（不带末尾斜杠，如 "https://memos.example.com"）
  /// [token]：Bearer Token（在 Memos → 设置 → Access Tokens 中生成）
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
  ///
  /// [pageSize]：单页条数（默认 100）
  /// [pageToken]：分页游标（首页为 null）
  /// [filter]：服务端过滤表达式（如 `'updateTime >= "2024-01-01T00:00:00Z"'`）
  ///
  /// 返回 memos 列表和下一页的 pageToken（最后一页时为 null）。
  Future<({List<Map<String, dynamic>> memos, String? nextPageToken})>
      listMemos({
    int pageSize = 100,
    String? pageToken,
    String? filter,
    String state = 'NORMAL',
  }) async {
    debugPrint('[API] listMemos pageSize=$pageSize, pageToken=$pageToken, filter=$filter state=$state');
    try {
      final params = <String, dynamic>{'pageSize': pageSize, 'state': state};
      if (pageToken != null) params['pageToken'] = pageToken;
      if (filter != null) params['filter'] = filter;

      final res = await _dio.get('/api/v1/memos', queryParameters: params);
      final memos =
          List<Map<String, dynamic>>.from(res.data['memos'] ?? []);
      final next = res.data['nextPageToken'] as String?;
      debugPrint('[API] listMemos 返回 ${memos.length} 条，nextPageToken=$next');
      return (
        memos: memos,
        nextPageToken: (next == null || next.isEmpty) ? null : next,
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 自动翻页，获取全部 memos
  ///
  /// [filter]：服务端过滤表达式，透传给每页请求。
  /// [state]：memo 状态（默认 NORMAL，传 "ARCHIVED" 获取归档列表）
  Future<List<Map<String, dynamic>>> listAllMemos({
    String? filter,
    String state = 'NORMAL',
  }) async {
    debugPrint('[API] listAllMemos 开始全量拉取，filter=$filter state=$state');
    final all = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final result = await listMemos(pageToken: pageToken, filter: filter, state: state);
      all.addAll(result.memos);
      pageToken = result.nextPageToken;
    } while (pageToken != null);
    debugPrint('[API] listAllMemos 全量拉取完成，共 ${all.length} 条');
    return all;
  }

  /// 在远端新建 memo
  ///
  /// [content]：Markdown 正文
  /// [visibility]：可见性（默认 PRIVATE）
  /// [attachmentNames]：已上传附件的资源名列表（如 ["attachments/xxx"]）
  ///
  /// 返回服务端创建的 memo 对象（含 name、createTime 等字段）。
  Future<Map<String, dynamic>> createMemo({
    required String content,
    String visibility = 'PRIVATE',
    List<String> attachmentNames = const [],
  }) async {
    debugPrint('[API] createMemo contentLen=${content.length} attachments=${attachmentNames.length}');
    try {
      final body = <String, dynamic>{
        'content': content,
        'visibility': visibility,
        if (attachmentNames.isNotEmpty)
          'attachments': attachmentNames.map((n) => {'name': n}).toList(),
      };
      final res = await _dio.post('/api/v1/memos', data: body);
      final result = Map<String, dynamic>.from(res.data);
      debugPrint('[API] createMemo 成功，name=${result["name"]}');
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 更新远端 memo（PATCH，只更新指定字段）
  ///
  /// [name]：资源名，如 `"memos/42"`
  /// [content]：新的 Markdown 正文
  /// [visibility]：新的可见性
  /// [attachmentNames]：附件资源名列表（如 ["attachments/xxx"]），传空列表则清空附件
  ///
  /// 通过 `updateMask` 告知服务端要更新的字段。
  Future<Map<String, dynamic>> updateMemo({
    required String name,
    required String content,
    String visibility = 'PRIVATE',
    List<String> attachmentNames = const [],
  }) async {
    debugPrint('[API] updateMemo name=$name, contentLen=${content.length} attachments=${attachmentNames.length}');
    try {
      final body = <String, dynamic>{
        'content': content,
        'visibility': visibility,
        'attachments': attachmentNames.map((n) => {'name': n}).toList(),
      };
      final res = await _dio.patch(
        '/api/v1/$name',
        data: body,
        queryParameters: {'updateMask': 'content,visibility,attachments'},
      );
      final result = Map<String, dynamic>.from(res.data);
      debugPrint('[API] updateMemo 成功，name=${result["name"]}');
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 归档远端 memo（state → ARCHIVED）
  Future<void> archiveMemo(String name) async {
    debugPrint('[API] archiveMemo name=$name');
    try {
      await _dio.patch(
        '/api/v1/$name',
        data: {'state': 'ARCHIVED'},
        queryParameters: {'updateMask': 'state'},
      );
      debugPrint('[API] archiveMemo 成功');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 取消归档远端 memo（state → NORMAL）
  Future<void> unarchiveMemo(String name) async {
    debugPrint('[API] unarchiveMemo name=$name');
    try {
      await _dio.patch(
        '/api/v1/$name',
        data: {'state': 'NORMAL'},
        queryParameters: {'updateMask': 'state'},
      );
      debugPrint('[API] unarchiveMemo 成功');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 删除远端 memo
  ///
  /// [name]：资源名，如 `"memos/42"`
  Future<void> deleteMemo(String name) async {
    debugPrint('[API] deleteMemo name=$name');
    try {
      await _dio.delete('/api/v1/$name');
      debugPrint('[API] deleteMemo 成功，name=$name');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ── Attachment CRUD (v0.25) ───────────────────────────────────

  /// 上传附件（POST /api/v1/attachments）
  ///
  /// v0.25 使用 JSON body，`content` 字段为文件内容的 base64 编码。
  /// 返回服务端附件对象，含 name / filename / type / size / externalLink 字段。
  ///
  /// [memoName]：可选，关联的 memo 资源名（如 "memos/abc123"），
  ///              传入后附件直接关联到对应 memo。
  Future<Map<String, dynamic>> uploadAttachment({
    required File file,
    required String filename,
    String? memoName,
  }) async {
    final mime = lookupMimeType(file.path) ?? 'application/octet-stream';
    final bytes = await file.readAsBytes();
    final base64Content = base64Encode(bytes);
    debugPrint('[API] uploadAttachment filename=$filename mime=$mime size=${bytes.length}B');
    try {
      final body = <String, dynamic>{
        'filename': filename,
        'content': base64Content,
        'type': mime,
        if (memoName != null) 'memo': memoName,
      };
      final res = await _dio.post('/api/v1/attachments', data: body);
      final result = Map<String, dynamic>.from(res.data as Map);
      debugPrint('[API] uploadAttachment 成功，name=${result["name"]}');
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// 删除远端附件
  ///
  /// [name]：附件资源名，如 `"attachments/123"`
  Future<void> deleteAttachment(String name) async {
    debugPrint('[API] deleteAttachment name=$name');
    try {
      await _dio.delete('/api/v1/$name');
      debugPrint('[API] deleteAttachment 成功');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ── User Stats ────────────────────────────────────────────────

  /// 获取指定用户的统计信息（标签计数等）
  ///
  /// [userName]：用户资源名，如 `"users/1"`（来自 auth/me 的 name 字段）。
  /// 返回原始响应 Map，含 `tagCount: { "标签名": 条数 }` 字段。
  Future<Map<String, dynamic>> getUserStats(String userName) async {
    debugPrint('[API] getUserStats user=$userName');
    try {
      final res = await _dio.get('/api/v1/$userName:getStats');
      final result = Map<String, dynamic>.from(res.data as Map);
      debugPrint('[API] getUserStats 成功，tagCount keys=${((result["tagCount"] as Map?)?.length ?? 0)}');
      return result;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ── Connection Test ───────────────────────────────────────────

  /// 测试连接：获取当前用户信息
  ///
  /// 优先调用 `/api/v1/auth/me`，若返回 404/405（部分旧版部署不支持该接口），
  /// 则回退到 `listMemos(pageSize: 1)` 验证 Token 是否有效。
  ///
  /// 返回用户对象（已解包 `{ "user": {...} }` 外层结构）。
  Future<Map<String, dynamic>> testConnection() async {
    debugPrint('[API] testConnection 开始');
    try {
      final res = await _dio.get('/api/v1/auth/me');
      final data = res.data;
      // v0.25 返回 { "user": { ... } }，取内层；旧版直接返回用户对象
      if (data is Map && data['user'] is Map) {
        final user = Map<String, dynamic>.from(data['user'] as Map);
        debugPrint('[API] testConnection 成功（v0.25），name=${user["name"]}');
        return user;
      }
      final user = Map<String, dynamic>.from(data as Map);
      debugPrint('[API] testConnection 成功，name=${user["name"]}');
      return user;
    } on DioException catch (e) {
      // 部分部署没有 auth/me 接口，回退用 listMemos 验证 Token
      if (e.response?.statusCode == 404 || e.response?.statusCode == 405) {
        debugPrint('[API] testConnection auth/me 不支持，回退到 listMemos 验证');
        try {
          await listMemos(pageSize: 1);
          debugPrint('[API] testConnection 回退验证成功');
          return {'name': 'users/me'};
        } on DioException catch (e2) {
          throw _wrap(e2);
        }
      }
      throw _wrap(e);
    }
  }

  // ── Error Wrapping ────────────────────────────────────────────

  /// 将 [DioException] 包装为用户友好的 [MemosApiException]
  MemosApiException _wrap(DioException e) {
    final code = e.response?.statusCode;
    debugPrint('[API] 请求失败 statusCode=$code, type=${e.type}, msg=${e.message}');

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
