import 'package:flutter/material.dart';

import '../../../services/agent/agent_models.dart';
import '../../../shared/constants/app_constants.dart';
import 'answer_view.dart';

/// 一次运行的卡片：随状态依次显示为计划卡、进度卡、改动预览卡、完成卡。
class RunCard extends StatelessWidget {
  final AgentRun run;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onCancel;
  final VoidCallback onApply;
  final VoidCallback onDiscard;
  final VoidCallback onRevert;
  final void Function(AgentChange change, bool include) onToggleChange;
  final void Function(AgentChange change, AgentMemoCandidate memo, bool include)
  onToggleMemo;
  final void Function(AgentChange change) onOpenResult;
  final void Function(String memoName) onOpenSource;

  const RunCard({
    super.key,
    required this.run,
    required this.busy,
    required this.onApprove,
    required this.onCancel,
    required this.onApply,
    required this.onDiscard,
    required this.onRevert,
    required this.onToggleChange,
    required this.onToggleMemo,
    required this.onOpenResult,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    // 提问：完成后直接显示答案，找日记的过程收在答案下方
    final answer = run.answer;
    if (run.isQuestion && answer != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnswerView(result: answer, onOpenSource: onOpenSource),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                '查找过程',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              children: _steps(showStatus: true),
            ),
          ),
        ],
      );
    }
    return AssistantBubble(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, size: 16, color: AppColors.primaryDark),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _heading,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (run.title.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              run.title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 10),
          ..._body(context),
        ],
      ),
    );
  }

  IconData get _icon => switch (run.status) {
    AgentRunStatus.awaitingApproval => Icons.assignment_outlined,
    AgentRunStatus.queued || AgentRunStatus.running => Icons.hourglass_top,
    AgentRunStatus.awaitingReview => Icons.fact_check_outlined,
    AgentRunStatus.applied || AgentRunStatus.done => Icons.check_circle_outline,
    AgentRunStatus.failed => Icons.error_outline,
    _ => Icons.info_outline,
  };

  String get _heading => switch (run.status) {
    AgentRunStatus.awaitingApproval => '我打算这样做',
    AgentRunStatus.queued => '排队中…',
    AgentRunStatus.running => run.isQuestion ? '正在翻日记…' : '执行中…',
    AgentRunStatus.awaitingReview => '请确认以下改动',
    AgentRunStatus.applying => '正在应用…',
    AgentRunStatus.applied => '已应用',
    AgentRunStatus.partiallyApplied => '部分已应用',
    AgentRunStatus.done => '完成，没有需要改动的内容',
    AgentRunStatus.discarded => '已放弃这些改动',
    AgentRunStatus.reverted => '已撤销',
    AgentRunStatus.partiallyReverted => '部分已撤销',
    AgentRunStatus.failed => '执行失败',
    AgentRunStatus.cancelled => '已取消',
  };

  List<Widget> _body(BuildContext context) {
    switch (run.status) {
      case AgentRunStatus.awaitingApproval:
        return [
          ..._steps(showStatus: false),
          if (run.llmCalls > 0)
            _note(
              '预计调用模型约 ${run.llmCalls} 次'
              '${run.modelName != null ? ' · ${run.modelName}（${run.cloudModel ? '云端，相关日记会发送给服务商' : '本地'}）' : ''}',
              warn: run.cloudModel,
            ),
          ..._notes(),
          const SizedBox(height: 8),
          const Text(
            '审阅改动前不会写入任何数据。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _buttons([
            _Btn('取消', onCancel, primary: false),
            _Btn('开始', onApprove),
          ]),
        ];
      case AgentRunStatus.queued:
      case AgentRunStatus.running:
        return [
          ..._steps(showStatus: true),
          const SizedBox(height: 8),
          _buttons([_Btn('取消', onCancel, primary: false)]),
        ];
      case AgentRunStatus.awaitingReview:
        final selected = run.changes.where((c) => c.selected).length;
        return [
          for (final c in run.changes)
            _ChangeTile(
              change: c,
              editable: !busy,
              onToggle: (v) => onToggleChange(c, v),
              onToggleMemo: (m, v) => onToggleMemo(c, m, v),
            ),
          ..._notes(),
          const SizedBox(height: 8),
          _buttons([
            _Btn('全部放弃', onDiscard, primary: false),
            _Btn('应用所选（$selected）', selected == 0 ? null : onApply),
          ]),
        ];
      case AgentRunStatus.applying:
        return [const LinearProgressIndicator()];
      case AgentRunStatus.applied:
      case AgentRunStatus.partiallyApplied:
      case AgentRunStatus.partiallyReverted:
      case AgentRunStatus.reverted:
        return [
          for (final c in run.changes)
            if (c.status != AgentChangeStatus.rejected)
              _OutcomeTile(change: c, onOpen: () => onOpenResult(c)),
          if (run.status.revertible) ...[
            const SizedBox(height: 8),
            _buttons([_Btn('撤销本次', onRevert, primary: false)]),
          ],
        ];
      case AgentRunStatus.failed:
        return [
          ..._steps(showStatus: true),
          if (run.error != null)
            Text(
              run.error!,
              style: const TextStyle(fontSize: 13, color: Colors.redAccent),
            ),
        ];
      case AgentRunStatus.done:
        return _steps(showStatus: true);
      case AgentRunStatus.discarded:
      case AgentRunStatus.cancelled:
        return const [];
    }
  }

  List<Widget> _steps({required bool showStatus}) => [
    for (final (i, s) in run.steps.indexed)
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child: showStatus
                  ? Icon(
                      switch (s.status) {
                        'DONE' => Icons.check,
                        'FAILED' => Icons.close,
                        'RUNNING' => Icons.autorenew,
                        _ => Icons.more_horiz,
                      },
                      size: 14,
                      color: switch (s.status) {
                        'FAILED' => Colors.redAccent,
                        'RUNNING' => AppColors.primary,
                        _ => Colors.grey,
                      },
                    )
                  : Text('${i + 1}.', style: const TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // 进行中的模型步骤显示「说明（进行中 2/5）」
                    s.status == 'RUNNING' && s.summary != null
                        ? '${s.label}（${s.summary}）'
                        : (s.summary ?? s.label),
                    style: const TextStyle(fontSize: 13),
                  ),
                  for (final d in s.details)
                    Text(
                      '· $d',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  if (s.error != null)
                    Text(
                      s.error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
  ];

  List<Widget> _notes() => [
    if (run.sensitiveExcluded > 0)
      _note('另有 ${run.sensitiveExcluded} 篇因敏感标签跳过'),
    if (run.coverageIgnored) _note('有日记服务端看不到最新内容，你选择了忽略', warn: true),
  ];

  Widget _note(String text, {bool warn = false}) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: warn ? Colors.orange[800] : Colors.grey[600],
      ),
    ),
  );

  Widget _buttons(List<_Btn> buttons) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      for (final b in buttons) ...[
        const SizedBox(width: 8),
        b.primary
            ? FilledButton(
                onPressed: busy ? null : b.onTap,
                child: Text(b.label),
              )
            : OutlinedButton(
                onPressed: busy ? null : b.onTap,
                child: Text(b.label),
              ),
      ],
    ],
  );
}

class _Btn {
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  const _Btn(this.label, this.onTap, {this.primary = true});
}

/// 审阅中的一条改动：整体勾选，事件串可展开逐篇勾选。
class _ChangeTile extends StatefulWidget {
  final AgentChange change;
  final bool editable;
  final ValueChanged<bool> onToggle;
  final void Function(AgentMemoCandidate memo, bool include) onToggleMemo;

  const _ChangeTile({
    required this.change,
    required this.editable,
    required this.onToggle,
    required this.onToggleMemo,
  });

  @override
  State<_ChangeTile> createState() => _ChangeTileState();
}

class _ChangeTileState extends State<_ChangeTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.change;
    final memos = c.memos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: c.selected,
              onChanged: widget.editable
                  ? (v) => widget.onToggle(v ?? false)
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.description, style: const TextStyle(fontSize: 13)),
                  if (c.staleSources > 0)
                    Text(
                      '有 ${c.staleSources} 篇来源日记在生成后被修改过',
                      style: TextStyle(fontSize: 11, color: Colors.orange[800]),
                    ),
                ],
              ),
            ),
            if (memos.isNotEmpty || c.op == AgentChangeOp.articleCreate)
              IconButton(
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                tooltip: _expanded
                    ? '收起'
                    : (memos.isNotEmpty ? '逐篇查看' : '预览全文'),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
          ],
        ),
        if (_expanded && c.op == AgentChangeOp.articleCreate)
          Container(
            margin: const EdgeInsets.only(left: 40, bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              c.payload['content'] as String? ?? '',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        if (_expanded && memos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Column(
              children: [
                for (final m in memos)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: m.include,
                    onChanged: widget.editable && c.selected
                        ? (v) => widget.onToggleMemo(m, v ?? false)
                        : null,
                    title: Text(
                      m.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    subtitle: Text(
                      [
                        if (m.displayTime != null) formatDate(m.displayTime!),
                        if (m.unsure) '拿不准',
                        if (m.excluded) '判断为不相关',
                        if (m.reason != null && m.reason!.isNotEmpty) m.reason!,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: m.excluded ? Colors.grey : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 应用 / 撤销后的一条改动结果。
class _OutcomeTile extends StatelessWidget {
  final AgentChange change;
  final VoidCallback onOpen;

  const _OutcomeTile({required this.change, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (change.status) {
      AgentChangeStatus.applied => (Icons.check, AppColors.primary, '已应用'),
      AgentChangeStatus.reverted => (Icons.undo, Colors.grey, '已撤销'),
      AgentChangeStatus.skipped => (
        Icons.remove_circle_outline,
        Colors.orange,
        '已跳过',
      ),
      AgentChangeStatus.failed => (Icons.error_outline, Colors.redAccent, '失败'),
      _ => (Icons.more_horiz, Colors.grey, ''),
    };
    final canOpen =
        change.status == AgentChangeStatus.applied &&
        change.result != null &&
        (change.op == AgentChangeOp.threadCreate ||
            change.op == AgentChangeOp.threadAddMembers ||
            change.op == AgentChangeOp.articleCreate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(change.description, style: const TextStyle(fontSize: 13)),
                Text(
                  [
                    label,
                    if (change.message != null) change.message!,
                  ].join(' · '),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (canOpen) TextButton(onPressed: onOpen, child: const Text('查看')),
        ],
      ),
    );
  }
}
