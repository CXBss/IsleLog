import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/services/agent/agent_api_client.dart';
import 'package:isle_log/services/agent/agent_models.dart';

/// 捕获请求并返回预设响应的 Dio。
(Dio, List<RequestOptions>) _dio(
  Object? Function(RequestOptions) respond, {
  int status = 200,
}) {
  final captured = <RequestOptions>[];
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured.add(options);
          final response = Response(
            requestOptions: options,
            statusCode: status,
            data: respond(options),
          );
          if (status >= 400) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: response,
                type: DioExceptionType.badResponse,
              ),
            );
          } else {
            handler.resolve(response);
          }
        },
      ),
    );
  return (dio, captured);
}

Map<String, dynamic> _run(String status) => {
  'name': 'agentRuns/5',
  'status': status,
  'title': 't',
  'instruction': 'i',
  'steps': [],
  'estimate': {},
  'coverage': {},
  'changes': [
    {
      'name': 'agentChanges/9',
      'seq': 1,
      'op': 'thread.add_members',
      'status': 'PROPOSED',
      'payload': {
        'title': '工作',
        'existingCount': 3,
        'memos': [
          {'id': 11, 'include': true, 'snippet': 'a'},
          {'id': 12, 'include': false, 'snippet': 'b'},
        ],
      },
      'staleSources': 2,
    },
  ],
};

void main() {
  test('发送消息带上覆盖度报告，并解析计划', () async {
    final (dio, captured) = _dio(
      (_) => {
        'messages': [
          {
            'name': 'agentMessages/1',
            'role': 'USER',
            'kind': 'TEXT',
            'body': {'text': 'x'},
          },
          {
            'name': 'agentMessages/2',
            'role': 'ASSISTANT',
            'kind': 'PLAN',
            'body': {'run': 5},
            'run': 'agentRuns/5',
          },
        ],
        'run': _run('AWAITING_APPROVAL'),
      },
    );
    final result = await AgentApiClient.fromDio(dio).postMessage(
      'agentSessions/7',
      'x',
      const SyncCoverage(conflictLocalIds: [1], ignored: true),
    );
    expect(captured.single.path, '/api/v1/agent/sessions/7/messages');
    expect((captured.single.data as Map)['coverage'], {
      'conflictLocalIds': [1],
      'ignored': true,
    });
    expect(result.messages.last.kind, AgentMessageKind.plan);
    expect(result.run!.status, AgentRunStatus.awaitingApproval);
  });

  test('应用时带 Idempotency-Key 请求头', () async {
    final (dio, captured) = _dio(
      (_) => {'outcome': {}, 'run': _run('APPLIED')},
    );
    final run = await AgentApiClient.fromDio(
      dio,
    ).apply('agentRuns/5', 'abc123');
    expect(captured.single.path, '/api/v1/agent/runs/5/apply');
    expect(captured.single.headers['Idempotency-Key'], 'abc123');
    expect(run.status, AgentRunStatus.applied);
  });

  test('逐篇勾选只发送变化的日记', () async {
    final (dio, captured) = _dio((_) => {'name': 'agentChanges/9'});
    await AgentApiClient.fromDio(
      dio,
    ).updateChange('agentChanges/9', memos: {'memos/12': true});
    expect(captured.single.method, 'PATCH');
    expect(captured.single.path, '/api/v1/agent/changes/9');
    expect(captured.single.data, {
      'memos': {'memos/12': true},
    });
  });

  test('解析改动：说明文字、候选日记与过期来源', () async {
    final (dio, _) = _dio((_) => _run('AWAITING_REVIEW'));
    final run = await AgentApiClient.fromDio(dio).getRun('agentRuns/5');
    final change = run.changes.single;
    expect(change.op, AgentChangeOp.threadAddMembers);
    expect(change.description, '往事件串「工作」新增 1 篇（已有 3 篇）');
    expect(change.memos.map((m) => m.memo), ['memos/11', 'memos/12']);
    expect(change.staleSources, 2);
  });

  test('服务端错误信息原样透传', () async {
    final (dio, _) = _dio(
      (_) => {'code': 423, 'message': '上一个任务还在执行'},
      status: 423,
    );
    await expectLater(
      AgentApiClient.fromDio(dio).approve('agentRuns/5'),
      throwsA(
        isA<AgentApiException>()
            .having((e) => e.message, 'message', '上一个任务还在执行')
            .having((e) => e.statusCode, 'statusCode', 423),
      ),
    );
  });

  test('未知状态视为格式错误', () {
    expect(
      () => AgentRun.fromJson({..._run('X'), 'status': 'WHATEVER'}),
      throwsA(isA<AgentApiException>()),
    );
  });
}
