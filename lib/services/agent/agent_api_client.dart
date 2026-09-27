import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../data/database/database_service.dart';
import '../settings/settings_service.dart';
import '../sync/sync_service.dart';
import 'agent_models.dart';

/// 日记助手网关，供页面注入 Fake 或真实实现。
abstract interface class AgentGateway {
  Future<AgentSession> createSession();

  /// 全部会话，最近更新的在前。
  Future<List<AgentSession>> listSessions();

  Future<void> deleteSession(String name);

  Future<AgentSessionDetail> getSession(String name);

  /// 发送一条消息。问答可能要等模型生成，耗时较长。
  Future<AgentPostResult> postMessage(
    String session,
    String text,
    SyncCoverage coverage,
  );

  Future<AgentRun> getRun(String name);

  Future<AgentRun> approve(String run);

  Future<AgentRun> cancel(String run);

  Future<AgentRun> discard(String run);

  /// 应用勾选的改动。[idempotencyKey] 相同的重试不会重复写入。
  Future<AgentRun> apply(String run, String idempotencyKey);

  Future<AgentRun> revert(String run);

  /// 整体勾选/取消一条改动，逐篇勾选候选日记（`memos/{id}` → 是否纳入），
  /// 或逐段接受改写（片段下标 → 是否采用）。
  Future<void> updateChange(
    String change, {
    bool? include,
    Map<String, bool>? memos,
    Map<int, bool>? segments,
  });
}

/// IsleLog 自建服务的日记助手客户端（`/api/v1/agent/*`）。
class AgentApiClient implements AgentGateway {
  final Dio _dio;

  AgentApiClient({required String baseUrl, required String token})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 10),
          // 问答要等模型生成，本地模型可能较慢
          receiveTimeout: const Duration(seconds: 180),
        ),
      );

  @visibleForTesting
  AgentApiClient.fromDio(this._dio);

  static String _id(String name) => name.substring(name.indexOf('/') + 1);

  Future<Map<String, dynamic>> _call(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final res = await request();
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw const AgentApiException('助手返回的数据格式无效');
      }
      return data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final message = body is Map<String, dynamic> ? body['message'] : null;
      if (message is String && message.isNotEmpty) {
        throw AgentApiException(message, statusCode: code);
      }
      if (e.response != null) {
        throw AgentApiException('助手请求失败（$code）', statusCode: code);
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        throw const AgentApiException('等待模型回复超时，请稍后再试');
      }
      throw const AgentApiException('无法连接服务器');
    }
  }

  @override
  Future<AgentSession> createSession() async => AgentSession.fromJson(
    await _call(() => _dio.post('/api/v1/agent/sessions')),
  );

  @override
  Future<List<AgentSession>> listSessions() async {
    final data = await _call(() => _dio.get('/api/v1/agent/sessions'));
    final list = data['sessions'];
    if (list is! List) throw const AgentApiException('助手返回的数据格式无效');
    return list
        .whereType<Map<String, dynamic>>()
        .map(AgentSession.fromJson)
        .toList();
  }

  @override
  Future<void> deleteSession(String name) async {
    await _call(() => _dio.delete('/api/v1/agent/sessions/${_id(name)}'));
  }

  @override
  Future<AgentSessionDetail> getSession(String name) async {
    final data = await _call(
      () => _dio.get('/api/v1/agent/sessions/${_id(name)}'),
    );
    final messages = data['messages'];
    final runs = data['runs'];
    final session = data['session'];
    if (messages is! List ||
        runs is! List ||
        session is! Map<String, dynamic>) {
      throw const AgentApiException('助手返回的数据格式无效');
    }
    final runMap = <String, AgentRun>{};
    for (final r in runs.whereType<Map<String, dynamic>>()) {
      final run = AgentRun.fromJson(r);
      runMap[run.name] = run;
    }
    return AgentSessionDetail(
      session: AgentSession.fromJson(session),
      messages: messages
          .whereType<Map<String, dynamic>>()
          .map(AgentMessage.fromJson)
          .toList(),
      runs: runMap,
    );
  }

  @override
  Future<AgentPostResult> postMessage(
    String session,
    String text,
    SyncCoverage coverage,
  ) async {
    debugPrint('[Agent] postMessage 字符数=${text.length}');
    final data = await _call(
      () => _dio.post(
        '/api/v1/agent/sessions/${_id(session)}/messages',
        data: {'text': text, 'coverage': coverage.toJson()},
      ),
    );
    final messages = data['messages'];
    if (messages is! List) throw const AgentApiException('助手返回的数据格式无效');
    final run = data['run'];
    return AgentPostResult(
      messages: messages
          .whereType<Map<String, dynamic>>()
          .map(AgentMessage.fromJson)
          .toList(),
      run: run is Map<String, dynamic> ? AgentRun.fromJson(run) : null,
    );
  }

  @override
  Future<AgentRun> getRun(String name) async => AgentRun.fromJson(
    await _call(() => _dio.get('/api/v1/agent/runs/${_id(name)}')),
  );

  Future<AgentRun> _action(String run, String action) async =>
      AgentRun.fromJson(
        await _call(() => _dio.post('/api/v1/agent/runs/${_id(run)}/$action')),
      );

  @override
  Future<AgentRun> approve(String run) => _action(run, 'approve');

  @override
  Future<AgentRun> cancel(String run) => _action(run, 'cancel');

  @override
  Future<AgentRun> discard(String run) => _action(run, 'discard');

  @override
  Future<AgentRun> apply(String run, String idempotencyKey) async {
    final data = await _call(
      () => _dio.post(
        '/api/v1/agent/runs/${_id(run)}/apply',
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      ),
    );
    final runJson = data['run'];
    if (runJson is! Map<String, dynamic>) {
      throw const AgentApiException('助手返回的数据格式无效');
    }
    return AgentRun.fromJson(runJson);
  }

  @override
  Future<AgentRun> revert(String run) async {
    final data = await _call(
      () => _dio.post('/api/v1/agent/runs/${_id(run)}/revert'),
    );
    final runJson = data['run'];
    if (runJson is! Map<String, dynamic>) {
      throw const AgentApiException('助手返回的数据格式无效');
    }
    return AgentRun.fromJson(runJson);
  }

  @override
  Future<void> updateChange(
    String change, {
    bool? include,
    Map<String, bool>? memos,
    Map<int, bool>? segments,
  }) async {
    await _call(
      () => _dio.patch(
        '/api/v1/agent/changes/${_id(change)}',
        data: {
          'include': ?include,
          'memos': ?memos,
          if (segments != null)
            'segments': {for (final e in segments.entries) '${e.key}': e.value},
        },
      ),
    );
  }
}

/// 解析网关、做发送前的同步与覆盖度检查。
class AgentService {
  final AgentGateway? _gateway;

  AgentService({AgentGateway? gateway}) : _gateway = gateway;

  Future<AgentGateway> gateway() async {
    final injected = _gateway;
    if (injected != null) return injected;
    final url = await SettingsService.serverUrl;
    final token = await SettingsService.accessToken;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      throw const AgentApiException('尚未配置服务器');
    }
    return AgentApiClient(baseUrl: url, token: token);
  }

  /// 先同步，再看有哪些日记服务端看不到最新内容。
  ///
  /// 只调一次 syncAll() 不等于服务端拿到了全集：冲突条目（conflict）永远不会
  /// 被推送，服务端只有旧版本；单条推送失败只打日志不上报。同步之后仍是
  /// conflict / pending 的，就是这两类。
  static Future<SyncCoverage> syncAndCheckCoverage() async {
    await SyncService.syncAll();
    final conflicts = await DatabaseService.getConflictMemos();
    final pending = await DatabaseService.getPendingSyncMemos();
    return SyncCoverage(
      conflictLocalIds: conflicts.map((m) => m.id).toList(),
      pushFailedLocalIds: pending.map((m) => m.id).toList(),
    );
  }
}
