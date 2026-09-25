import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isle_log/features/assistant/assistant_page.dart';
import 'package:isle_log/services/agent/agent_api_client.dart';
import 'package:isle_log/services/agent/agent_models.dart';
import 'package:isle_log/services/ai/ai_api_client.dart';
import 'package:isle_log/services/ai/ai_models.dart';

Map<String, dynamic> _runJson(
  String status, {
  List<Map<String, dynamic>> changes = const [],
  Map<String, dynamic> coverage = const {},
}) => {
  'name': 'agentRuns/1',
  'status': status,
  'title': '把 #跑步 的日记放进事件串「跑步记录」',
  'instruction': '把 #跑步 的日记放进事件串「跑步记录」',
  'steps': [
    {'id': 's1', 'label': '找到带 #跑步 的日记 2 篇', 'status': 'DONE'},
    {'id': 's2', 'label': '事件串「跑步记录」不存在，将新建', 'status': 'DONE'},
  ],
  'estimate': {'memos': 2, 'sensitiveExcluded': 1},
  'coverage': coverage,
  'changes': changes,
};

Map<String, dynamic> _threadChange(String status, {bool nightRun = true}) => {
  'name': 'agentChanges/9',
  'seq': 1,
  'op': 'thread.create',
  'status': status,
  'payload': {
    'title': '跑步记录',
    'memos': [
      {
        'id': 11,
        'include': true,
        'snippet': '晨跑 5 公里',
        'displayTs': 1758700000,
      },
      {'id': 12, 'include': nightRun, 'snippet': '夜跑', 'displayTs': 1758710000},
    ],
  },
  if (status == 'APPLIED') 'result': 'threads/77',
};

class _FakeAgent implements AgentGateway {
  final posted = <(String, SyncCoverage)>[];
  final updates = <Map<String, Object?>>[];
  final actions = <String>[];
  String? applyKey;

  /// 下一条消息的回复：问答或计划
  bool planNext = false;
  Map<String, dynamic> run = _runJson('AWAITING_APPROVAL');

  AgentMessage _msg(
    String role,
    String kind,
    Map<String, dynamic> body, [
    String? run,
  ]) => AgentMessage.fromJson({
    'name': 'agentMessages/${posted.length}$role',
    'role': role,
    'kind': kind,
    'body': body,
    'run': ?run,
  });

  @override
  Future<AgentSession> createSession() async =>
      const AgentSession(name: 'agentSessions/1', title: '');

  @override
  Future<AgentSessionDetail> getSession(String name) =>
      throw UnimplementedError();

  @override
  Future<AgentPostResult> postMessage(
    String session,
    String text,
    SyncCoverage coverage,
  ) async {
    posted.add((text, coverage));
    final user = _msg('USER', 'TEXT', {'text': text});
    if (planNext) {
      return AgentPostResult(
        messages: [
          user,
          _msg('ASSISTANT', 'PLAN', {'run': 1}, 'agentRuns/1'),
        ],
        run: AgentRun.fromJson(run),
      );
    }
    if (text.contains('错误')) {
      return AgentPostResult(
        messages: [
          user,
          _msg('ASSISTANT', 'ERROR', {'message': '记忆检索未启用'}),
        ],
      );
    }
    return AgentPostResult(
      messages: [
        user,
        _msg('ASSISTANT', 'ANSWER', {
          'answer': '你去过厦门和黄山。',
          'sources': [
            {
              'memo': 'memos/1',
              'displayTime': '2025-07-12T10:00:00Z',
              'snippet': '厦门的海',
              'similarity': 0.8,
            },
          ],
          'insufficientEvidence': false,
          'indexIncomplete': false,
        }),
      ],
    );
  }

  @override
  Future<AgentRun> getRun(String name) async => AgentRun.fromJson(run);

  Future<AgentRun> _act(String action, String next) async {
    actions.add(action);
    run = {...run, 'status': next};
    return AgentRun.fromJson(run);
  }

  @override
  Future<AgentRun> approve(String r) async {
    actions.add('approve');
    // 执行很快：审批后第一次轮询就进入待审阅
    run = _runJson('AWAITING_REVIEW', changes: [_threadChange('PROPOSED')]);
    return AgentRun.fromJson(_runJson('QUEUED'));
  }

  @override
  Future<AgentRun> cancel(String r) => _act('cancel', 'CANCELLED');

  @override
  Future<AgentRun> discard(String r) => _act('discard', 'DISCARDED');

  @override
  Future<AgentRun> apply(String r, String key) async {
    actions.add('apply');
    applyKey = key;
    run = _runJson(
      'APPLIED',
      changes: [_threadChange('APPLIED', nightRun: false)],
    );
    return AgentRun.fromJson(run);
  }

  @override
  Future<AgentRun> revert(String r) async {
    actions.add('revert');
    run = _runJson(
      'REVERTED',
      changes: [_threadChange('REVERTED', nightRun: false)],
    );
    return AgentRun.fromJson(run);
  }

  @override
  Future<void> updateChange(
    String change, {
    bool? include,
    Map<String, bool>? memos,
  }) async {
    updates.add({'change': change, 'include': include, 'memos': memos});
    if (memos != null && memos['memos/12'] == false) {
      run = _runJson(
        'AWAITING_REVIEW',
        changes: [_threadChange('PROPOSED', nightRun: false)],
      );
    }
  }
}

class _FakeAi implements AiGateway {
  @override
  Future<List<AiProviderStatus>> listProviders() async => const [
    AiProviderStatus(
      name: AiProvider.local,
      enabled: true,
      available: true,
      model: 'qwen3.8',
      contextLength: 131072,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<_FakeAgent> _pump(
  WidgetTester tester, {
  SyncCoverage coverage = const SyncCoverage(),
  List<String>? synced,
}) async {
  final agent = _FakeAgent();
  await tester.pumpWidget(
    MaterialApp(
      home: AssistantPage(
        gateway: agent,
        aiGateway: _FakeAi(),
        coverageCheck: () async => coverage,
        afterApply: () async => synced?.add('sync'),
        pollInterval: const Duration(milliseconds: 10),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return agent;
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byTooltip('发送'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空状态展示示例指令和当前模型', (tester) async {
    await _pump(tester);
    expect(find.text('问问你的日记，或让我帮你整理'), findsOneWidget);
    expect(find.text('把 #跑步 的日记放进事件串「跑步记录」'), findsOneWidget);
    expect(find.text('使用 qwen3.8（本地）'), findsOneWidget);
  });

  testWidgets('提问后展示答案和来源卡片', (tester) async {
    final agent = await _pump(tester);
    await _send(tester, '去年夏天我去过哪些地方？');

    expect(find.text('去年夏天我去过哪些地方？'), findsOneWidget);
    expect(find.text('你去过厦门和黄山。'), findsOneWidget);
    expect(find.text('厦门的海'), findsOneWidget);
    expect(agent.posted.single.$2.complete, isTrue);
  });

  testWidgets('失败的回复以错误消息展示', (tester) async {
    await _pump(tester);
    await _send(tester, '制造一个错误');
    expect(find.text('记忆检索未启用'), findsOneWidget);
  });

  testWidgets('有日记服务端看不到最新内容时先提醒；取消则不发送', (tester) async {
    final agent = await _pump(
      tester,
      coverage: const SyncCoverage(
        conflictLocalIds: [3],
        pushFailedLocalIds: [4, 5],
      ),
    );
    await _send(tester, '去年夏天我去过哪些地方？');
    expect(find.text('AI 有 3 篇日记看不到最新内容'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(agent.posted, isEmpty);
  });

  testWidgets('选择忽略并继续时照常发送，并带上忽略标记', (tester) async {
    final agent = await _pump(
      tester,
      coverage: const SyncCoverage(pushFailedLocalIds: [4]),
    );
    await _send(tester, '去年夏天我去过哪些地方？');
    await tester.tap(find.text('忽略并继续'));
    await tester.pumpAndSettle();

    expect(agent.posted.single.$2.ignored, isTrue);
    expect(agent.posted.single.$2.toJson()['pushFailedLocalIds'], [4]);
  });

  testWidgets('计划 → 开始 → 逐篇勾选 → 应用 → 撤销', (tester) async {
    final synced = <String>[];
    final agent = await _pump(tester, synced: synced);
    agent.planNext = true;
    await _send(tester, '把 #跑步 的日记放进事件串「跑步记录」');

    // 计划卡
    expect(find.text('我打算这样做'), findsOneWidget);
    expect(find.text('另有 1 篇因敏感标签跳过'), findsOneWidget);
    expect(find.text('审阅改动前不会写入任何数据。'), findsOneWidget);
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    // 轮询进入改动预览
    expect(find.text('请确认以下改动'), findsOneWidget);
    expect(find.text('新建事件串「跑步记录」，放入 2 篇'), findsOneWidget);

    // 展开并取消勾选夜跑
    await tester.tap(find.byTooltip('逐篇查看'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('夜跑'));
    await tester.pumpAndSettle();
    expect(agent.updates.single['memos'], {'memos/12': false});
    expect(find.text('新建事件串「跑步记录」，放入 1 篇'), findsOneWidget);

    await tester.tap(find.text('应用所选（1）'));
    await tester.pumpAndSettle();
    expect(agent.actions, containsAllInOrder(['approve', 'apply']));
    expect(agent.applyKey, isNotEmpty);
    expect(synced, ['sync'], reason: '应用后要拉取结果');
    expect(find.text('已应用'), findsWidgets);

    await tester.tap(find.text('撤销本次'));
    await tester.pumpAndSettle();
    expect(agent.actions.last, 'revert');
    expect(find.text('已撤销'), findsWidgets);
  });

  testWidgets('计划卡可以取消', (tester) async {
    final agent = await _pump(tester);
    agent.planNext = true;
    await _send(tester, '把 #跑步 的日记放进事件串「跑步记录」');
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();
    expect(agent.actions, ['cancel']);
    expect(find.text('已取消'), findsOneWidget);
  });
}
