import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../services/agent/agent_api_client.dart';
import '../../services/agent/agent_models.dart';
import '../../services/ai/ai_api_client.dart';
import '../../services/ai/ai_models.dart';
import '../../services/ai/ai_service.dart';
import '../../services/settings/settings_service.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/constants/app_constants.dart';
import '../articles/article_editor_page.dart';
import '../memo_detail/memo_detail_page.dart';
import '../memo_editor/ai/ai_action_sheet.dart' show aiModelLabel;
import '../threads/thread_detail_page.dart';
import 'widgets/answer_view.dart';
import 'widgets/run_card.dart';

/// AI 助手：合并了原来的记忆检索。
///
/// 提问 → 回答卡（答案 + 来源日记）；布置任务 → 计划卡 → 进度卡 → 改动预览卡
/// → 完成卡。任何写入都要在预览卡里确认后才发生，应用后可以整体撤销。
/// 会话与运行保存在服务端，这里只记住最近一次会话的名字。
class AssistantPage extends StatefulWidget {
  /// 测试注入；为 null 时按服务器设置创建真实客户端。
  final AgentGateway? gateway;
  final AiGateway? aiGateway;

  /// 发送前的同步与覆盖度检查，测试可替换。
  final Future<SyncCoverage> Function()? coverageCheck;

  /// 应用改动后拉取结果，测试可替换。
  final Future<void> Function()? afterApply;

  /// 轮询间隔，测试可调小。
  final Duration pollInterval;

  const AssistantPage({
    super.key,
    this.gateway,
    this.aiGateway,
    this.coverageCheck,
    this.afterApply,
    this.pollInterval = const Duration(seconds: 1),
  });

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  AgentGateway? _gateway;
  String? _session;
  final List<AgentMessage> _messages = [];
  final Map<String, AgentRun> _runs = {};
  final Set<String> _busyRuns = {};

  /// 发出去还没回来的问题，显示为「正在思考」
  String? _pending;
  bool _loading = true;
  String? _modelLabel;
  Timer? _poll;

  static const _examples = [
    '去年夏天我去过哪些地方？',
    '总结过去两个月的日记，分类整理成文章放到「文章总结」目录',
    '找出与大模型相关的所有日记，放进一个事件串',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 后台不轮询；回到前台补拉一次
    if (state == AppLifecycleState.resumed) {
      _refreshRuns();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _init() async {
    try {
      _gateway = widget.gateway ?? await AgentService().gateway();
      _loadModelLabel();
      final last = widget.gateway == null
          ? await SettingsService.agentLastSession
          : null;
      if (last != null) {
        try {
          await _loadSession(last);
        } on AgentApiException {
          await SettingsService.setAgentLastSession(null);
        }
      }
    } on AgentApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadModelLabel() async {
    try {
      final ai = widget.aiGateway ?? await AiService().createGateway();
      final statuses = await ai.listProviders();
      if (mounted) setState(() => _modelLabel = aiModelLabel(statuses));
    } on AiApiException {
      // 只是展示用，取不到不影响
    }
  }

  Future<void> _loadSession(String name) async {
    final detail = await _gateway!.getSession(name);
    if (!mounted) return;
    setState(() {
      _session = detail.session.name;
      _messages
        ..clear()
        ..addAll(detail.messages);
      _runs
        ..clear()
        ..addAll(detail.runs);
    });
    _ensurePolling();
    _scrollToBottom();
  }

  void _newSession() {
    _poll?.cancel();
    _poll = null;
    SettingsService.setAgentLastSession(null);
    setState(() {
      _session = null;
      _messages.clear();
      _runs.clear();
    });
  }

  // ── 发送 ─────────────────────────────────────────────────────

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    final gateway = _gateway;
    if (text.isEmpty || _pending != null || gateway == null) return;

    // 发送前先同步，并检查有没有日记服务端看不到最新内容
    setState(() => _pending = text);
    SyncCoverage coverage;
    try {
      coverage =
          await (widget.coverageCheck ?? AgentService.syncAndCheckCoverage)();
    } catch (_) {
      coverage = const SyncCoverage();
    }
    if (!mounted) return;
    if (!coverage.complete) {
      // 问用户的时候不显示「正在思考」
      setState(() => _pending = null);
      final decision = await _confirmCoverage(coverage);
      if (!mounted || decision != true) return;
      coverage = coverage.asIgnored();
      setState(() => _pending = text);
    }

    _input.clear();
    _scrollToBottom();
    try {
      var session = _session;
      if (session == null) {
        session = (await gateway.createSession()).name;
        _session = session;
        if (widget.gateway == null) {
          await SettingsService.setAgentLastSession(session);
        }
      }
      final result = await gateway.postMessage(session, text, coverage);
      if (!mounted) return;
      setState(() {
        _messages.addAll(result.messages);
        final run = result.run;
        if (run != null) _runs[run.name] = run;
      });
    } on AgentApiException catch (e) {
      if (mounted) {
        _input.text = text; // 发送失败时把原文还给用户
        _snack(e.message);
      }
    } finally {
      if (mounted) setState(() => _pending = null);
      _scrollToBottom();
    }
  }

  /// 覆盖度提醒：规划之前告诉用户 AI 看不到哪些日记的最新内容。
  /// 返回 true 表示忽略并继续。
  Future<bool?> _confirmCoverage(SyncCoverage c) {
    final conflicts = c.conflictLocalIds.length;
    final failed = c.pushFailedLocalIds.length;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('AI 有 ${conflicts + failed} 篇日记看不到最新内容'),
        content: Text(
          [
            if (conflicts > 0) '· $conflicts 篇存在同步冲突（本地版本还没上传）',
            if (failed > 0) '· $failed 篇推送失败',
            '',
            'AI 只能看到这些日记在服务器上的旧版本，结果可能不准确。',
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          if (conflicts > 0)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
                _openLocalMemo(c.conflictLocalIds.first);
              },
              child: const Text('先处理'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('忽略并继续'),
          ),
        ],
      ),
    );
  }

  // ── 运行 ─────────────────────────────────────────────────────

  Future<void> _runAction(
    AgentRun run,
    Future<AgentRun> Function(AgentGateway g) action, {
    bool syncAfter = false,
  }) async {
    if (_busyRuns.contains(run.name)) return;
    setState(() => _busyRuns.add(run.name));
    try {
      final updated = await action(_gateway!);
      if (!mounted) return;
      setState(() => _runs[updated.name] = updated);
      if (syncAfter) {
        // 结果在服务端，拉下来后「查看」才能打开本地条目
        await (widget.afterApply ?? () => SyncService.syncAll().then((_) {}))();
      }
      _ensurePolling();
    } on AgentApiException catch (e) {
      _snack(e.message);
      await _refreshRun(run.name);
    } finally {
      if (mounted) setState(() => _busyRuns.remove(run.name));
    }
  }

  Future<void> _toggleChange(
    AgentRun run,
    AgentChange change,
    bool include,
  ) async {
    await _review(
      run,
      () => _gateway!.updateChange(change.name, include: include),
    );
  }

  Future<void> _toggleMemo(
    AgentRun run,
    AgentChange change,
    AgentMemoCandidate memo,
    bool include,
  ) async {
    await _review(
      run,
      () => _gateway!.updateChange(change.name, memos: {memo.memo: include}),
    );
  }

  Future<void> _review(AgentRun run, Future<void> Function() update) async {
    if (_busyRuns.contains(run.name)) return;
    setState(() => _busyRuns.add(run.name));
    try {
      await update();
      await _refreshRun(run.name);
    } on AgentApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busyRuns.remove(run.name));
    }
  }

  Future<void> _refreshRun(String name) async {
    try {
      final run = await _gateway!.getRun(name);
      if (mounted) setState(() => _runs[name] = run);
    } on AgentApiException {
      // 下一次轮询再试
    }
  }

  Future<void> _refreshRuns() async {
    for (final name in _runs.keys.toList()) {
      if (_runs[name]!.status.inProgress) await _refreshRun(name);
    }
    _ensurePolling();
  }

  /// 有运行还在服务端推进时每秒轮询一次，全部停下后停止。
  void _ensurePolling() {
    final active = _runs.values.any((r) => r.status.inProgress);
    if (!active) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(widget.pollInterval, (_) => _refreshRuns());
  }

  String _idempotencyKey() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  // ── 跳转 ─────────────────────────────────────────────────────

  Future<void> _openSource(String memoName) async {
    final memo = await DatabaseService.getMemoByMemosName(memoName);
    if (memo == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemoDetailPage(memo: memo)),
    );
  }

  Future<void> _openLocalMemo(int id) async {
    final memo = await DatabaseService.getMemoById(id);
    if (memo == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemoDetailPage(memo: memo)),
    );
  }

  /// 按远端名打开产物：本地 id 要等同步完成后才有。
  Future<void> _openResult(AgentChange change) async {
    final result = change.result;
    if (result == null) return;
    if (change.op == AgentChangeOp.articleCreate) {
      // 本地文章按 memos/{id} 记录远端名（文章复用 memos 表）
      final article = await DatabaseService.getArticleByArticleName(
        result.replaceFirst('articles/', 'memos/'),
      );
      if (!mounted) return;
      if (article == null) {
        _snack('还在同步结果，请稍后再试');
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ArticleEditorPage(editingArticle: article, openInPreview: true),
        ),
      );
      return;
    }
    final thread = await DatabaseService.getThreadByThreadName(result);
    if (!mounted) return;
    if (thread == null) {
      _snack('还在同步结果，请稍后再试');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ThreadDetailPage(threadId: thread.id)),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── 界面 ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text(
          'AI 助手',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (_session != null)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: '新对话',
              onPressed: _newSession,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(child: _buildList()),
                  _buildInput(),
                ],
              ),
      ),
    );
  }

  Widget _buildList() {
    if (_messages.isEmpty && _pending == null) return _buildEmpty();
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        for (final m in _messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildMessage(m),
          ),
        if (_pending != null) ...[
          UserBubble(text: _pending!),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                '正在思考…',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMessage(AgentMessage m) {
    if (m.isUser) return UserBubble(text: m.text);
    switch (m.kind) {
      case AgentMessageKind.answer:
        return AnswerView(result: m.answer!, onOpenSource: _openSource);
      case AgentMessageKind.plan:
        final run = _runs[m.run];
        if (run == null) return const SizedBox.shrink();
        return RunCard(
          run: run,
          busy: _busyRuns.contains(run.name),
          onApprove: () => _runAction(run, (g) => g.approve(run.name)),
          onCancel: () => _runAction(run, (g) => g.cancel(run.name)),
          onDiscard: () => _runAction(run, (g) => g.discard(run.name)),
          onApply: () => _runAction(
            run,
            (g) => g.apply(run.name, _idempotencyKey()),
            syncAfter: true,
          ),
          onRevert: () =>
              _runAction(run, (g) => g.revert(run.name), syncAfter: true),
          onToggleChange: (c, v) => _toggleChange(run, c, v),
          onToggleMemo: (c, memo, v) => _toggleMemo(run, c, memo, v),
          onOpenResult: _openResult,
        );
      case AgentMessageKind.clarify:
        return AssistantBubble(
          child: Text(
            m.body['question'] as String? ?? '',
            style: const TextStyle(fontSize: 14),
          ),
        );
      case AgentMessageKind.error:
        return AssistantBubble(
          child: Text(
            m.body['message'] as String? ?? '出错了',
            style: const TextStyle(fontSize: 14, color: Colors.redAccent),
          ),
        );
      case AgentMessageKind.text:
      case AgentMessageKind.unknown:
        return const SizedBox.shrink();
    }
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 56,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              '问问你的日记，或让我帮你整理',
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              '回答只依据你写过的日记；任何改动都要你确认后才会写入',
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final e in _examples)
                  ActionChip(label: Text(e), onPressed: () => _send(e)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    final sending = _pending != null;
    return Material(
      color: AppColors.surface(context),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_modelLabel != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    '使用 $_modelLabel',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !sending,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: '问问你的日记，或让我帮你整理…',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending ? null : () => _send(),
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: '发送',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
