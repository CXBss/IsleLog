/// 日记助手（Journal Agent）的数据模型，与服务端 `/api/v1/agent/*` 对应。
///
/// 会话、消息、运行的权威数据都在服务端，客户端不落 Isar。
library;

import '../ai/ai_models.dart';

/// 助手接口的错误。
class AgentApiException implements Exception {
  final String message;
  final int? statusCode;

  const AgentApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

Never _invalid() => throw const AgentApiException('助手返回的数据格式无效');

DateTime? _time(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

class AgentSession {
  final String name;
  final String title;
  final DateTime? updateTime;

  const AgentSession({
    required this.name,
    required this.title,
    this.updateTime,
  });

  factory AgentSession.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String) _invalid();
    return AgentSession(
      name: name,
      title: json['title'] as String? ?? '',
      updateTime: _time(json['updateTime']),
    );
  }
}

/// 消息种类。
enum AgentMessageKind { text, answer, plan, clarify, error, unknown }

class AgentMessage {
  final String name;

  /// USER / ASSISTANT
  final String role;
  final AgentMessageKind kind;
  final Map<String, dynamic> body;

  /// PLAN 消息引用的运行
  final String? run;

  const AgentMessage({
    required this.name,
    required this.role,
    required this.kind,
    required this.body,
    this.run,
  });

  bool get isUser => role == 'USER';

  /// 用户消息的原文。
  String get text => body['text'] as String? ?? '';

  /// ANSWER 消息的问答结果（与记忆检索接口同形）。
  MemorySearchResult? get answer => kind == AgentMessageKind.answer
      ? MemorySearchResult.fromJson(body)
      : null;

  factory AgentMessage.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final role = json['role'];
    final body = json['body'];
    if (name is! String || role is! String) _invalid();
    return AgentMessage(
      name: name,
      role: role,
      kind: switch (json['kind']) {
        'TEXT' => AgentMessageKind.text,
        'ANSWER' => AgentMessageKind.answer,
        'PLAN' => AgentMessageKind.plan,
        'CLARIFY' => AgentMessageKind.clarify,
        'ERROR' => AgentMessageKind.error,
        _ => AgentMessageKind.unknown,
      },
      body: body is Map<String, dynamic> ? body : const {},
      run: json['run'] as String?,
    );
  }
}

/// 运行状态。
enum AgentRunStatus {
  awaitingApproval,
  queued,
  running,
  awaitingReview,
  applying,
  applied,
  partiallyApplied,
  done,
  discarded,
  reverted,
  partiallyReverted,
  failed,
  cancelled;

  static AgentRunStatus parse(Object? v) => switch (v) {
    'AWAITING_APPROVAL' => awaitingApproval,
    'QUEUED' => queued,
    'RUNNING' => running,
    'AWAITING_REVIEW' => awaitingReview,
    'APPLYING' => applying,
    'APPLIED' => applied,
    'PARTIALLY_APPLIED' => partiallyApplied,
    'DONE' => done,
    'DISCARDED' => discarded,
    'REVERTED' => reverted,
    'PARTIALLY_REVERTED' => partiallyReverted,
    'FAILED' => failed,
    'CANCELLED' => cancelled,
    _ => _invalid(),
  };

  /// 还在服务端推进中，需要轮询。
  bool get inProgress => this == queued || this == running || this == applying;

  /// 已应用（可以撤销）。
  bool get revertible =>
      this == applied || this == partiallyApplied || this == partiallyReverted;
}

class AgentStep {
  final String id;

  /// 操作名，如 memos.search、llm.answer
  final String op;
  final String label;

  /// PENDING / RUNNING / DONE / FAILED
  final String status;
  final String? summary;
  final String? error;

  /// foreach 每一项的进度（「写成《工作》（引用 12 篇）」）
  final List<String> details;

  const AgentStep({
    required this.id,
    this.op = '',
    required this.label,
    required this.status,
    this.summary,
    this.error,
    this.details = const [],
  });

  factory AgentStep.fromJson(Map<String, dynamic> json) => AgentStep(
    id: json['id'] as String? ?? '',
    op: json['op'] as String? ?? '',
    label: json['label'] as String? ?? '',
    status: json['status'] as String? ?? 'PENDING',
    summary: json['summary'] as String?,
    error: json['error'] as String?,
    details:
        (json['details'] as List?)?.whereType<String>().toList() ?? const [],
  );
}

/// 事件串候选日记：用户可以逐篇勾选。
class AgentMemoCandidate {
  /// `memos/{id}`
  final String memo;
  final bool include;
  final String snippet;
  final DateTime? displayTime;
  final String? reason;

  /// 模型拿不准（默认不勾）
  final bool unsure;

  /// 模型判断为不相关（默认不勾）
  final bool excluded;

  const AgentMemoCandidate({
    required this.memo,
    required this.include,
    required this.snippet,
    this.displayTime,
    this.reason,
    this.unsure = false,
    this.excluded = false,
  });

  factory AgentMemoCandidate.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final ts = json['displayTs'];
    return AgentMemoCandidate(
      memo: 'memos/$id',
      include: json['include'] == true,
      snippet: json['snippet'] as String? ?? '',
      displayTime: ts is num
          ? DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000)
          : null,
      reason: json['reason'] as String?,
      unsure: json['unsure'] == true,
      excluded: json['excluded'] == true,
    );
  }
}

/// 暂存改动的种类。
enum AgentChangeOp {
  folderCreate,
  articleCreate,
  threadCreate,
  threadAddMembers,
  memoRewrite,
  memoMerge,
  memoArchive,
  unknown;

  /// 会修改已有日记：本机有未同步修改的日记不能应用，否则下次同步必然冲突。
  bool get touchesMemo =>
      this == memoRewrite || this == memoMerge || this == memoArchive;
}

/// 改写预览里的一段：原文 → 改写，可逐段接受。
class AgentRewriteSegment {
  final int index;
  final String originalText;
  final String revisedText;
  final String? reason;

  /// 改动碰到了标签、链接、待办、日期或数值，默认不勾选
  final bool protectedChanged;
  final bool accept;

  const AgentRewriteSegment({
    required this.index,
    required this.originalText,
    required this.revisedText,
    this.reason,
    this.protectedChanged = false,
    this.accept = false,
  });

  bool get changed => originalText != revisedText;

  factory AgentRewriteSegment.fromJson(int index, Map<String, dynamic> json) =>
      AgentRewriteSegment(
        index: index,
        originalText: json['originalText'] as String? ?? '',
        revisedText: json['revisedText'] as String? ?? '',
        reason: json['reason'] as String?,
        protectedChanged: json['protectedElementsChanged'] == true,
        accept: json['accept'] == true,
      );
}

/// 暂存改动状态。
enum AgentChangeStatus {
  proposed,
  rejected,
  applied,
  skipped,
  failed,
  reverted,
}

class AgentChange {
  final String name;
  final int seq;
  final AgentChangeOp op;
  final AgentChangeStatus status;
  final Map<String, dynamic> payload;
  final String? message;

  /// 新建对象的资源名（`threads/1` 等），应用后才有
  final String? result;

  /// 生成之后又被修改过的来源日记数
  final int staleSources;

  const AgentChange({
    required this.name,
    required this.seq,
    required this.op,
    required this.status,
    required this.payload,
    this.message,
    this.result,
    this.staleSources = 0,
  });

  bool get selected => status == AgentChangeStatus.proposed;

  /// 标题：事件串 / 文件夹 / 文章名。
  String get title => payload['title'] as String? ?? '';

  /// 改写 / 合并 / 归档的目标日记（`memos/{id}`）。
  String? get targetMemo {
    final id = payload['memoId'];
    return op.touchesMemo && id != null ? 'memos/$id' : null;
  }

  /// 目标日记的摘要与日期（改写、归档用）。
  String get snippet => payload['snippet'] as String? ?? '';
  DateTime? get displayTime {
    final ts = payload['displayTs'];
    return ts is num
        ? DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000)
        : null;
  }

  /// 改写的逐段对照（含未改动的段落）。
  List<AgentRewriteSegment> get segments {
    final list = payload['segments'];
    if (list is! List) return const [];
    return [
      for (final (i, s) in list.indexed)
        if (s is Map<String, dynamic>) AgentRewriteSegment.fromJson(i, s),
    ];
  }

  /// 合并时其余被归档的日记。
  List<AgentMemoCandidate> get mergeSources {
    final list = payload['sources'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => AgentMemoCandidate.fromJson({...m, 'include': true}))
        .toList();
  }

  /// 被合并日记上的评论总数（评论留在归档的原日记上）。
  int get mergeComments {
    final list = payload['sources'];
    if (list is! List) return 0;
    return list.whereType<Map<String, dynamic>>().fold(
      0,
      (n, m) => n + ((m['comments'] as num?)?.toInt() ?? 0),
    );
  }

  List<AgentMemoCandidate> get memos {
    final list = payload['memos'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(AgentMemoCandidate.fromJson)
        .toList();
  }

  /// 一句话说明这条改动。
  String get description {
    final included = memos.where((m) => m.include).length;
    final date = displayTime == null ? '' : '${_md(displayTime!)} ';
    return switch (op) {
      AgentChangeOp.memoRewrite => () {
        final segs = segments.where((s) => s.changed);
        final accepted = segs.where((s) => s.accept).length;
        return '改写 $date「${_short(snippet)}」（采用 $accepted/${segs.length} 处）';
      }(),
      AgentChangeOp.memoMerge =>
        '把 ${mergeSources.length + 1} 篇合并进 $date「${_short(snippet.isEmpty ? (payload['content'] as String? ?? '') : snippet)}」',
      AgentChangeOp.memoArchive => '归档 $date「${_short(snippet)}」',
      AgentChangeOp.threadCreate => '新建事件串「$title」，放入 $included 篇',
      AgentChangeOp.threadAddMembers =>
        '往事件串「$title」新增 $included 篇（已有 ${payload['existingCount'] ?? 0} 篇）',
      AgentChangeOp.folderCreate => '新建文件夹「$title」',
      AgentChangeOp.articleCreate =>
        '新建文章《$title》${payload['folder'] != null ? '（放入「${payload['folder']}」）' : ''}',
      AgentChangeOp.unknown => '未知改动',
    };
  }

  factory AgentChange.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final seq = json['seq'];
    if (name is! String || seq is! int) _invalid();
    final payload = json['payload'];
    return AgentChange(
      name: name,
      seq: seq,
      op: switch (json['op']) {
        'folder.create' => AgentChangeOp.folderCreate,
        'article.create' => AgentChangeOp.articleCreate,
        'thread.create' => AgentChangeOp.threadCreate,
        'thread.add_members' => AgentChangeOp.threadAddMembers,
        'memo.rewrite' => AgentChangeOp.memoRewrite,
        'memo.merge' => AgentChangeOp.memoMerge,
        'memo.archive' => AgentChangeOp.memoArchive,
        _ => AgentChangeOp.unknown,
      },
      status: switch (json['status']) {
        'PROPOSED' => AgentChangeStatus.proposed,
        'REJECTED' => AgentChangeStatus.rejected,
        'APPLIED' => AgentChangeStatus.applied,
        'SKIPPED' => AgentChangeStatus.skipped,
        'FAILED' => AgentChangeStatus.failed,
        'REVERTED' => AgentChangeStatus.reverted,
        _ => _invalid(),
      },
      payload: payload is Map<String, dynamic> ? payload : const {},
      message: json['message'] as String?,
      result: json['result'] as String?,
      staleSources: (json['staleSources'] as num?)?.toInt() ?? 0,
    );
  }
}

String _md(DateTime t) => '${t.month}月${t.day}日';

String _short(String s) {
  final line = s.trim().split('\n').first;
  return line.length > 16 ? '${line.substring(0, 16)}…' : line;
}

class AgentRun {
  final String name;
  final AgentRunStatus status;
  final String title;
  final String instruction;
  final List<AgentStep> steps;
  final Map<String, dynamic> estimate;
  final Map<String, dynamic> coverage;
  final String? error;
  final List<AgentChange> changes;

  /// 提问类计划的答案（与记忆检索结果同形），运行完成后才有。
  final MemorySearchResult? answer;

  const AgentRun({
    required this.name,
    required this.status,
    required this.title,
    required this.instruction,
    required this.steps,
    required this.estimate,
    required this.coverage,
    this.error,
    this.changes = const [],
    this.answer,
  });

  /// 只读的提问计划：没有写入步骤。
  bool get isQuestion => steps.any((s) => s.op == 'llm.answer');

  /// 预计调用模型的次数（0 表示不调用模型）。
  int get llmCalls => (estimate['llmCalls'] as num?)?.toInt() ?? 0;

  /// 这次会用的模型名，以及是否云端。
  String? get modelName => estimate['model'] as String?;
  bool get cloudModel => estimate['cloud'] == true;

  /// 因敏感标签被跳过的篇数。
  int get sensitiveExcluded =>
      (estimate['sensitiveExcluded'] as num?)?.toInt() ?? 0;

  /// 发送时有日记服务端看不到最新内容，用户选择了忽略。
  bool get coverageIgnored => coverage['ignored'] == true;

  factory AgentRun.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String) _invalid();
    final steps = json['steps'];
    final changes = json['changes'];
    return AgentRun(
      name: name,
      status: AgentRunStatus.parse(json['status']),
      title: json['title'] as String? ?? '',
      instruction: json['instruction'] as String? ?? '',
      steps: steps is List
          ? steps
                .whereType<Map<String, dynamic>>()
                .map(AgentStep.fromJson)
                .toList()
          : const [],
      estimate: json['estimate'] is Map<String, dynamic>
          ? json['estimate'] as Map<String, dynamic>
          : const {},
      coverage: json['coverage'] is Map<String, dynamic>
          ? json['coverage'] as Map<String, dynamic>
          : const {},
      error: json['error'] as String?,
      answer: json['answer'] is Map<String, dynamic>
          ? MemorySearchResult.fromJson(json['answer'] as Map<String, dynamic>)
          : null,
      changes: changes is List
          ? changes
                .whereType<Map<String, dynamic>>()
                .map(AgentChange.fromJson)
                .toList()
          : const [],
    );
  }
}

/// 一次会话的完整内容。
class AgentSessionDetail {
  final AgentSession session;
  final List<AgentMessage> messages;
  final Map<String, AgentRun> runs;

  const AgentSessionDetail({
    required this.session,
    required this.messages,
    required this.runs,
  });
}

/// 发送消息的结果：用户消息 + 助手回复（问答 / 计划 / 澄清 / 错误）。
class AgentPostResult {
  final List<AgentMessage> messages;
  final AgentRun? run;

  const AgentPostResult({required this.messages, this.run});
}

/// 发送前的覆盖度报告：这些本地日记服务端看不到最新内容。
class SyncCoverage {
  final List<int> conflictLocalIds;
  final List<int> pushFailedLocalIds;
  final bool ignored;

  const SyncCoverage({
    this.conflictLocalIds = const [],
    this.pushFailedLocalIds = const [],
    this.ignored = false,
  });

  bool get complete => conflictLocalIds.isEmpty && pushFailedLocalIds.isEmpty;

  SyncCoverage asIgnored() => SyncCoverage(
    conflictLocalIds: conflictLocalIds,
    pushFailedLocalIds: pushFailedLocalIds,
    ignored: true,
  );

  Map<String, dynamic> toJson() => {
    if (conflictLocalIds.isNotEmpty) 'conflictLocalIds': conflictLocalIds,
    if (pushFailedLocalIds.isNotEmpty) 'pushFailedLocalIds': pushFailedLocalIds,
    if (ignored) 'ignored': true,
  };
}
